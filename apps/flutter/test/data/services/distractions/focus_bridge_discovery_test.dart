import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/distractions/focus_bridge_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

const origin = 'chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
FocusBridge bridge({int? port, SharedPreferences? preferences}) => FocusBridge(
  owner: 'owner',
  flavor: 'development',
  listenPort: port,
  preferences: preferences,
  state: () async => {'session': null},
  command: (command) async => command,
);

Future<(int, Map<String, dynamic>)> post(
  FocusBridge server,
  String path,
  Map<String, dynamic> body, {
  String source = origin,
  String? host,
  String? token,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    request.headers.set('Origin', source);
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    if (host != null) request.headers.set('Host', host);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    return (
      response.statusCode,
      jsonDecode(await response.transform(utf8.decoder).join())
          as Map<String, dynamic>,
    );
  } finally {
    client.close(force: true);
  }
}

void main() {
  test(
    'occupied preferred port falls back, persists, and concurrent start is idempotent',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final occupied = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(occupied.close);
      final server = bridge(port: occupied.port, preferences: preferences);
      addTearDown(server.dispose);
      await Future.wait([server.start(), server.start()]);
      expect(server.error, isNull);
      final selected = server.port;
      expect(selected, isNot(occupied.port));
      expect(List.generate(64, (i) => 51989 + 3 * i), contains(selected));
      await server.start();
      expect(server.port, selected);
      await server.dispose();
      final restarted = bridge(preferences: preferences);
      addTearDown(restarted.dispose);
      await restarted.start();
      expect(restarted.error, isNull);
      expect(restarted.port, selected);
    },
  );

  test(
    'conflicting instances keep separate servers and disposal cancels startup',
    () async {
      final first = bridge();
      addTearDown(first.dispose);
      await first.start();
      final conflict = bridge(port: first.port);
      addTearDown(conflict.dispose);
      await conflict.start();
      expect(conflict.error, isNull);
      expect(conflict.port, isNot(first.port));
      final closing = bridge(port: 0);
      await Future.wait([closing.start(), closing.dispose()]);
      await closing.start();
      expect(closing.port, 0);
    },
  );

  test(
    'non-conflict errors are retained rather than selecting another port',
    () async {
      final server = bridge(port: -1);
      addTearDown(server.dispose);
      await server.start();
      expect(server.error, isNotNull);
      expect(server.port, -1);
    },
  );

  test(
    'exhaustion is explicit and a later successful start clears the error',
    () async {
      final occupied = <ServerSocket>[];
      addTearDown(() async {
        for (final socket in occupied) {
          await socket.close();
        }
      });
      for (var i = 0; i < 64; i++) {
        try {
          occupied.add(
            await ServerSocket.bind(
              InternetAddress.loopbackIPv4,
              51989 + 3 * i,
            ),
          );
        } on SocketException {
          /* An existing listener also occupies this candidate. */
        }
      }
      expect(occupied, isNotEmpty);
      final server = bridge();
      addTearDown(server.dispose);
      await server.start();
      expect(server.error, isNotNull);
      expect(server.pair, throwsStateError);
      final released = occupied.removeLast();
      final availablePort = released.port;
      await released.close();
      await server.start();
      expect(server.error, isNull);
      expect(server.port, availablePort);
    },
  );

  test(
    'pairing survives a restart onto a different port and accepts legacy codes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final first = bridge(preferences: preferences);
      addTearDown(first.dispose);
      await first.start();
      final code = first.pair().split('-').last;
      final paired = await post(first, '/pair', {
        'code': code,
        'deviceId': 'browser',
        'flavor': 'development',
      });
      expect(paired.$1, 200);
      final token = paired.$2['token'] as String;
      final oldPort = first.port;
      await first.dispose();
      final occupied = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        oldPort,
      );
      addTearDown(occupied.close);
      final restarted = bridge(preferences: preferences);
      addTearDown(restarted.dispose);
      await restarted.start();
      expect(restarted.error, isNull);
      expect(restarted.port, isNot(oldPort));
      final discovered = await post(restarted, '/discover', {
        'clientId': sha256.convert(utf8.encode(token)).toString(),
        'challenge': 'a' * 43,
        'flavor': 'development',
      });
      expect(discovered.$1, 200);
      expect(discovered.$2['port'], restarted.port);
      expect(
        (await post(restarted, '/command', {
          'action': 'read',
        }, token: token)).$1,
        200,
      );
    },
  );

  test(
    'discovery proves the paired token and pins origin, flavor, account, port and nonce',
    () async {
      final server = bridge(port: 0);
      addTearDown(server.dispose);
      await server.start();
      final code = server.pair();
      expect(code, matches(RegExp('^${server.port}-[0-9]{6}\$')));
      final paired = await post(server, '/pair', {
        'code': code,
        'deviceId': 'browser',
        'flavor': 'development',
      });
      expect(paired.$1, 200);
      expect(paired.$2['discoveryVersion'], 1);
      final token = paired.$2['token'] as String;
      final challenge = base64UrlEncode(
        List.generate(32, (i) => i),
      ).replaceAll('=', '');
      final body = {
        'clientId': sha256.convert(utf8.encode(token)).toString(),
        'challenge': challenge,
        'flavor': 'development',
      };
      final discovered = await post(server, '/discover', body);
      expect(discovered.$1, 200);
      final payload = jsonEncode([
        'pomodoist-bridge-discovery-v1',
        challenge,
        'owner',
        'development',
        server.port,
      ]);
      expect(discovered.$2, {
        'version': 1,
        'owner': 'owner',
        'flavor': 'development',
        'port': server.port,
        'proof': Hmac(
          sha256,
          utf8.encode(token),
        ).convert(utf8.encode(payload)).toString(),
      });
      expect(jsonEncode(discovered.$2), isNot(contains(token)));
      expect(
        (await post(
          server,
          '/discover',
          body,
          source: 'https://evil.example',
        )).$1,
        403,
      );
      expect(
        (await post(
          server,
          '/discover',
          body,
          source: 'chrome-extension://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        )).$1,
        403,
      );
      expect(
        (await post(
          server,
          '/discover',
          body,
          host: 'localhost:${server.port}',
        )).$1,
        403,
      );
      expect((await post(server, '/discover?x=1', body)).$1, 403);
      expect(
        (await post(server, '/discover', {...body, 'flavor': 'production'})).$1,
        403,
      );
      expect(
        (await post(server, '/discover', {...body, 'challenge': 'short'})).$1,
        400,
      );
      expect(
        (await post(server, '/discover', {...body, 'padding': 'x' * 65536})).$1,
        400,
      );
      await server.revoke();
      expect((await post(server, '/discover', body)).$1, 403);
    },
  );
}
