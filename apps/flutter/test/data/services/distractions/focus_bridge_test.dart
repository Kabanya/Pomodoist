import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/distractions/focus_bridge_io.dart';

void main() {
  test(
    'loopback requires extension origin, one-use code, pinned token, bounded commands',
    () async {
      final bridge = FocusBridge(
        owner: 'owner',
        flavor: 'development',
        listenPort: 0,
        state: () async => {'session': null},
        command: (c) async => {'action': c['action']},
      );
      await bridge.start();
      expect(bridge.error, isNull);
      final client = HttpClient();
      const origin = 'chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      Future<(int, Map)> request(
        String path, {
        String source = origin,
        String? token,
        Map? body,
      }) async {
        final r = await client.openUrl(
          body == null ? 'GET' : 'POST',
          Uri.parse('http://127.0.0.1:${bridge.port}$path'),
        );
        r.headers.set('Origin', source);
        if (token != null) r.headers.set('Authorization', 'Bearer $token');
        if (body != null) {
          r.headers.contentType = ContentType.json;
          r.write(jsonEncode(body));
        }
        final response = await r.close();
        return (
          response.statusCode,
          jsonDecode(await response.transform(utf8.decoder).join()) as Map,
        );
      }

      try {
        expect(
          (await request('/state', source: 'https://evil.example')).$1,
          403,
        );
        final code = bridge.pair();
        final paired = await request(
          '/pair',
          body: {'code': code, 'deviceId': 'browser', 'flavor': 'development'},
        );
        expect(paired.$1, 200);
        final token = paired.$2['token'] as String;
        expect(
          (await request(
            '/pair',
            body: {
              'code': code,
              'deviceId': 'browser',
              'flavor': 'development',
            },
          )).$1,
          403,
        );
        expect((await request('/state', token: token)).$1, 200);
        expect(
          (await request(
            '/state',
            token: token,
            source: 'chrome-extension://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          )).$1,
          401,
        );
        expect(
          (await request(
            '/command',
            token: token,
            body: {'action': 'shell.execute'},
          )).$1,
          400,
        );
        await bridge.revoke();
        expect((await request('/state', token: token)).$1, 401);
      } finally {
        client.close(force: true);
        await bridge.dispose();
      }
    },
  );
}
