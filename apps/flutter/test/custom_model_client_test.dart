@TestOn('vm')
library;

import 'package:pomodoist/domain/models/settings/custom_model_config.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/planning/custom_model_client.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/data/services/planning/task_decomposition_prompt.dart';

void main() {
  group('model base URLs', () {
    for (final entry in {
      ' HTTPS://API.example:443/openai/v1/ ': 'https://api.example/openai/v1',
      'http://localhost:8000/': 'http://localhost:8000',
      'http://127.4.3.2:8000/v1': 'http://127.4.3.2:8000/v1',
      'http://[::1]:8000/v1/': 'http://[::1]:8000/v1',
      'http://[0:0:0:0:0:0:0:1]:8000/v1/': 'http://[::1]:8000/v1',
    }.entries) {
      test('canonicalizes ${entry.key}', () {
        expect(
          CustomModelClient.parseBaseUrl(entry.key).toString(),
          entry.value,
        );
      });
    }
    for (final value in [
      '',
      'localhost/v1',
      'http://model.example/v1',
      'http://localhost.example/v1',
      'http://127.0.0.1.example/v1',
      'http://192.168.1.2/v1',
      'ftp://localhost',
      'http://127.00.0.1',
      'https://user:private@model.example/v1',
      'https://@model.example/v1',
      'https://model.example/v1?token=private',
      'https://model.example/v1#private',
      'https:///v1',
      'https://model.example:65536/v1',
      r'http://localhost\@model.example/v1',
    ]) {
      test('rejects invalid base URL ${value.hashCode}', () {
        expect(
          () => CustomModelClient.parseBaseUrl(value),
          throwsA(
            isA<FormatException>().having(
              (e) => e.toString(),
              'error',
              isNot(contains('private')),
            ),
          ),
        );
      });
    }
  });

  test('the direct and managed clients use the same decomposition rules', () {
    final serverSource = File(
      '../../server/supabase/functions/_shared/task_decomposition.ts',
    ).readAsStringSync();
    expect(
      serverSource,
      contains(
        'export const taskDecompositionPrompt = `\n$taskDecompositionPrompt\n`.trim();',
      ),
    );
  });

  const client = CustomModelClient();
  const key = 'private-api-test-token';
  const transcript = 'Приватный текст для анализа';
  final now = DateTime(2026, 11, 22, 12, 30);

  Future<HttpServer> serve(Future<void> Function(HttpRequest) handle) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen(handle);
    return server;
  }

  Future<List<DecomposedTaskDraft>> request(
    int port, {
    bool smart = false,
    String token = key,
    CustomModelClient service = client,
  }) => service.decompose(
    baseUrl: Uri.parse('http://127.0.0.1:$port/custom/v1/'),
    apiKey: token,
    model: 'my/chosen-model',
    transcript: transcript,
    now: now,
    locale: 'ru-RU',
    smartMode: smart,
  );

  for (final smart in [false, true]) {
    test(
      'sends only model context and decodes 15 complete drafts (smart=$smart)',
      () async {
        final capture = Completer<(String?, String?, String, Uri, Map)>();
        final server = await serve((r) async {
          final body = jsonDecode(await utf8.decoder.bind(r).join()) as Map;
          capture.complete((
            r.headers.value('authorization'),
            r.headers.contentType?.mimeType,
            r.method,
            r.uri,
            body,
          ));
          r.response.write(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'tasks': List.generate(
                        15,
                        (i) => {
                          'quickAdd': 'Задача $i p2 #work 3p 2026-11-23',
                          'description': 'Заметка $i',
                          'subtasks': [
                            {
                              'quickAdd': 'Дочерняя',
                              'subtasks': [
                                {'quickAdd': 'Подробнее'},
                              ],
                            },
                          ],
                        },
                      ),
                    }),
                  },
                },
              ],
            }),
          );
          await r.response.close();
        });
        final drafts = await request(server.port, smart: smart);
        final (auth, mime, method, uri, body) = await capture.future;
        expect(auth, 'Bearer $key');
        expect(mime, 'application/json');
        expect(method, 'POST');
        expect(uri.toString(), '/custom/v1/chat/completions');
        expect(body.keys, unorderedEquals(['model', 'messages']));
        expect(body['model'], 'my/chosen-model');
        final messages = body['messages'] as List;
        expect(messages.length, 2);
        expect(messages.first['role'], 'system');
        expect(messages.first['content'], startsWith(taskDecompositionPrompt));
        expect(messages.first['content'] == taskDecompositionPrompt, !smart);
        expect(messages.last['role'], 'user');
        final userMessage = messages.last['content'] as String;
        expect(userMessage, startsWith('Locale: ru-RU\nCurrent local time: '));
        expect(userMessage, endsWith('\n\nTranscript:\n$transcript'));
        expect(
          DateTime.parse(
            userMessage.split('\n')[1].substring('Current local time: '.length),
          ).isAtSameMomentAs(now),
          isTrue,
        );
        expect(drafts.length, 15);
        expect(drafts.last.quickAdd, 'Задача 14 p2 #work 3p 2026-11-23');
        expect(drafts.last.description, 'Заметка 14');
        expect(
          drafts.last.subtasks.single.subtasks.single.quickAdd,
          'Подробнее',
        );
      },
    );
  }

  Matcher code(ModelCheck expected) => throwsA(
    isA<CustomModelException>()
        .having((e) => e.code, 'code', expected)
        .having(
          (e) => e.toString(),
          'message',
          allOf(isNot(contains(key)), isNot(contains(transcript))),
        ),
  );

  for (final entry in {
    401: ModelCheck.unauthorized,
    403: ModelCheck.unauthorized,
    429: ModelCheck.rateLimited,
    500: ModelCheck.provider,
    200: ModelCheck.invalidResponse,
  }.entries) {
    test('sanitizes HTTP ${entry.key} errors', () async {
      final server = await serve((r) async {
        r.response.statusCode = entry.key;
        r.response.write('$key $transcript');
        await r.response.close();
      });
      await expectLater(request(server.port), code(entry.value));
    });
  }

  test('does not follow redirects or forward a token', () async {
    var redirected = false;
    final target = await serve((r) async {
      redirected = true;
      await r.response.close();
    });
    final server = await serve(
      (r) => r.response.redirect(
        Uri.parse('http://127.0.0.1:${target.port}/other'),
        status: 307,
      ),
    );
    await expectLater(request(server.port), code(ModelCheck.provider));
    expect(redirected, isFalse);
  });

  test('optional empty token sends no Authorization header', () async {
    final auth = Completer<String?>();
    final server = await serve((r) async {
      auth.complete(r.headers.value('authorization'));
      r.response.write('{"tasks":["local task"]}');
      await r.response.close();
    });
    expect(
      (await request(server.port, token: '')).single.quickAdd,
      'local task',
    );
    expect(await auth.future, isNull);
  });

  test('maps network and timeout failures without private details', () async {
    final hanging = await serve((r) async {});
    await expectLater(
      request(
        hanging.port,
        service: const CustomModelClient(
          fastTimeout: Duration(milliseconds: 100),
        ),
      ),
      code(ModelCheck.timeout),
    );
    final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    await expectLater(request(port), code(ModelCheck.network));
  });
}
