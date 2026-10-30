import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The bridge accepts only extension origins, paired by a locally displayed code.
class FocusBridge {
  FocusBridge({
    required this.owner,
    required this.flavor,
    required this.state,
    required this.command,
    this.preferences,
    this.listenPort,
  });
  final String owner, flavor;
  final int? listenPort;
  final Future<Map<String, dynamic>> Function() state;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) command;
  final SharedPreferences? preferences;
  HttpServer? _server;
  Future<void>? _starting;
  bool _disposed = false;
  String? pairingCode, error;
  DateTime? _codeExpiry;
  final _random = Random.secure();
  final Map<String, Map<String, String>> _clients = {};
  int _failures = 0;
  DateTime _failureWindow = DateTime.now();
  List<int> get _ports {
    final base = switch (flavor) {
      'staging' => 51988,
      'development' => 51989,
      _ => 51987,
    };
    return List.generate(64, (i) => base + 3 * i);
  }

  int get port => _server?.port ?? listenPort ?? _ports.first;
  String get _key => 'focusBridge.$flavor.$owner';
  String get _portKey => '$_key.port';
  String _secret() =>
      base64UrlEncode(List.generate(32, (_) => _random.nextInt(256)));
  String pair() {
    if (_server == null || _disposed) {
      throw StateError('Desktop bridge is unavailable.');
    }
    pairingCode = '$port-${100000 + _random.nextInt(900000)}';
    _codeExpiry = DateTime.now().add(const Duration(seconds: 120));
    return pairingCode!;
  }

  Future<void> start() {
    if (_disposed || _server != null) return Future.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    try {
      final saved = preferences?.getString(_key);
      if (saved != null) {
        try {
          for (final e in (jsonDecode(saved) as Map).entries) {
            _clients[e.key as String] = Map<String, String>.from(e.value);
          }
        } on Object {
          _clients.clear();
          await preferences?.remove(_key);
        }
      }
      final savedPort = preferences?.get(_portKey);
      final candidates = listenPort == 0
          ? [0]
          : <int>{
              if (listenPort != null)
                listenPort!
              else if (savedPort is int && _ports.contains(savedPort))
                savedPort,
              ..._ports,
            };
      for (final candidate in candidates) {
        if (_disposed) return;
        HttpServer server;
        try {
          server = await HttpServer.bind(
            InternetAddress.loopbackIPv4,
            candidate,
            shared: false,
          );
        } on SocketException catch (e) {
          // Dart also reports an in-process bind conflict with its own shared-flag error.
          final conflict =
              const [48, 98, 10048].contains(e.osError?.errorCode) ||
              (e.osError?.errorCode == -1 &&
                  (e.osError?.message.startsWith('The shared flag to bind()') ??
                      false));
          if (!conflict || candidate == candidates.last) rethrow;
          continue;
        }
        if (_disposed) {
          await server.close(force: true);
          return;
        }
        _server = server;
        error = null;
        server.listen((r) => unawaited(_handle(r)));
        if (listenPort == null || _ports.contains(server.port)) {
          await preferences?.setInt(_portKey, server.port);
        }
        return;
      }
    } on Object catch (e) {
      error = e.toString();
    }
  }

  bool _equal(String a, String b) {
    var n = a.length ^ b.length;
    for (var i = 0; i < a.length; i++) {
      n |= a.codeUnitAt(i) ^ (i < b.length ? b.codeUnitAt(i) : 0);
    }
    return n == 0;
  }

  Future<Map<String, dynamic>> _body(HttpRequest r) async {
    var size = 0;
    final bytes = <int>[];
    await for (final part in r.timeout(const Duration(seconds: 5))) {
      size += part.length;
      if (size > 65536) throw const FormatException('Message too large');
      bytes.addAll(part);
    }
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  }

  Future<void> _handle(HttpRequest r) async {
    final origin = r.headers.value('origin') ?? '';
    final validOrigin = RegExp(
      r'^chrome-extension://[a-p]{32}$',
    ).hasMatch(origin);
    Future<void> respond(int status, Object body) async {
      r.response.statusCode = status;
      r.response.headers.contentType = ContentType.json;
      r.response.headers.set('Cache-Control', 'no-store');
      r.response.write(jsonEncode(body));
      await r.response.close();
    }

    if (r.headers.value('host') != '127.0.0.1:$port' ||
        !validOrigin ||
        r.uri.hasQuery) {
      await respond(403, {'error': 'forbidden'});
      return;
    }
    r.response.headers.set('Access-Control-Allow-Origin', origin);
    r.response.headers.set('Vary', 'Origin');
    if (r.method == 'OPTIONS') {
      r.response.headers.set(
        'Access-Control-Allow-Methods',
        'GET, POST, OPTIONS',
      );
      r.response.headers.set(
        'Access-Control-Allow-Headers',
        'Authorization, Content-Type',
      );
      await respond(204, {});
      return;
    }
    try {
      if (r.uri.path == '/discover' && r.method == 'POST') {
        final body = await _body(r);
        final id = body['clientId'], challenge = body['challenge'];
        if (id is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
            challenge is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(challenge)) {
          await respond(400, {'error': 'invalid_discovery'});
          return;
        }
        String? matchedToken;
        if (body['flavor'] == flavor) {
          for (final entry in _clients.entries) {
            if (entry.value['origin'] == origin &&
                _equal(sha256.convert(utf8.encode(entry.key)).toString(), id)) {
              matchedToken = entry.key;
              break;
            }
          }
        }
        if (matchedToken == null) {
          await respond(403, {'error': 'discovery_unavailable'});
          return;
        }
        final payload = jsonEncode([
          'pomodoist-bridge-discovery-v1',
          challenge,
          owner,
          flavor,
          port,
        ]);
        final proof = Hmac(
          sha256,
          utf8.encode(matchedToken),
        ).convert(utf8.encode(payload)).toString();
        await respond(200, {
          'version': 1,
          'owner': owner,
          'flavor': flavor,
          'port': port,
          'proof': proof,
        });
        return;
      }
      if (r.uri.path == '/pair' && r.method == 'POST') {
        if (DateTime.now().difference(_failureWindow) >
            const Duration(minutes: 1)) {
          _failures = 0;
          _failureWindow = DateTime.now();
        }
        final body = await _body(r);
        if (_failures >= 5 ||
            pairingCode == null ||
            _codeExpiry == null ||
            DateTime.now().isAfter(_codeExpiry!) ||
            (!_equal('${body['code']}', pairingCode!) &&
                !_equal('${body['code']}', pairingCode!.split('-').last)) ||
            body['flavor'] != flavor ||
            body['deviceId'] is! String ||
            ('${body['deviceId']}').length > 128) {
          _failures++;
          await respond(403, {'error': 'invalid_pairing'});
          return;
        }
        pairingCode = null;
        _codeExpiry = null;
        final token = _secret();
        _clients[token] = {'origin': origin, 'deviceId': body['deviceId']};
        await preferences?.setString(_key, jsonEncode(_clients));
        await respond(200, {
          'token': token,
          'owner': owner,
          'flavor': flavor,
          'discoveryVersion': 1,
        });
        return;
      }
      final auth = r.headers.value('authorization') ?? '';
      final token = auth.startsWith('Bearer ') ? auth.substring(7) : '';
      final client = _clients[token];
      if (client == null || client['origin'] != origin) {
        await respond(401, {'error': 'unpaired'});
        return;
      }
      if (r.uri.path == '/state' && r.method == 'GET') {
        await respond(200, await state());
        return;
      }
      if (r.uri.path == '/command' && r.method == 'POST') {
        final body = await _body(r);
        if (!const [
          'read',
          'start',
          'startReady',
          'pause',
          'resume',
          'restart',
          'changePreset',
          'complete',
          'skip',
          'requestStop',
          'cancelStop',
          'detach',
          'registerDevice',
          'profileUpsert',
          'assignmentUpsert',
        ].contains(body['action'])) {
          await respond(400, {'error': 'unsupported_command'});
          return;
        }
        body['deviceId'] = client['deviceId'];
        await respond(200, await command(body));
        return;
      }
      await respond(404, {'error': 'not_found'});
    } on TimeoutException {
      await respond(503, {'error': 'temporarily_unavailable'});
    } on SocketException {
      await respond(503, {'error': 'temporarily_unavailable'});
    } on Object {
      await respond(400, {'error': 'invalid_request'});
    }
  }

  Future<void> revoke() async {
    _clients.clear();
    pairingCode = null;
    await preferences?.remove(_key);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _starting;
    pairingCode = null;
    await _server?.close(force: true);
    _server = null;
  }
}
