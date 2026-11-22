@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:app_voice/app_voice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/billing_dependencies.dart';
import 'package:pomodoist/config/custom_model_access.dart';
import 'package:pomodoist/config/custom_model_settings_dependencies.dart';
import 'package:pomodoist/config/voice_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/audio/focus_sound_player.dart';
import 'package:pomodoist/config/voice_preferences_dependencies.dart';
import 'package:pomodoist/config/voice_task_route.dart';
import 'package:pomodoist/data/repositories/settings/custom_model_repository.dart';
import 'package:pomodoist/data/repositories/voice/voice_preferences_repository_impl.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/data/services/planning/custom_model_client.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/models/settings/custom_model_config.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';
import 'package:pomodoist/ui/voice/view_models/voice_quick_add_view_model.dart';

import '../testing/fakes/fake_account_client.dart';
import '../testing/fakes/fake_task_decomposer.dart';

const _transcript = 'Позвонить Анне. Купить билеты.';
const _base = 'https://my-model.example/v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final smart in [false, true]) {
    test(
      'permanent access after Pro expiry uses local dictation, reviews and saves the selected model drafts (smart=$smart)',
      () async {
        final flow = _Flow();
        await flow.open();
        await flow.model.setSmartMode(smart);
        await pumpEventQueue();
        await flow.record();
        expect(flow.client.requests, [
          (
            url: _base,
            model: smart ? 'careful-model' : 'fast-model',
            key: 'fixture-key',
            text: _transcript,
            locale: 'ru-RU',
            smart: smart,
          ),
        ]);
        expect(flow.settings.keyReads, [_base]);
        final state = flow.model.state;
        expect(state.error, isNull);
        expect(state.canStart, isTrue);
        expect(state.drafts.single.description, 'Перед поездкой');
        expect(state.drafts.single.subtasks.single.quickAdd, 'Купить билеты');
        expect(flow.saved, isEmpty);
        final edited = DecomposedTaskDraft(
          quickAdd: 'Позвонить Анне завтра p1',
          description: state.drafts.single.description,
          subtasks: state.drafts.single.subtasks,
        );
        expect(await flow.model.save([edited], projectId: 'trip'), [
          'saved-id',
        ]);
        expect(flow.saved.single.drafts, [edited]);
        expect(flow.saved.single.project, 'trip');
        expect(flow.model.state.saving, isFalse);
      },
    );
  }

  test(
    'Smart dictation sends the transcript to the displayed loopback endpoint and saves 15 reviewed tasks in Drift',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final titles = List.generate(
        15,
        (index) => 'Проверить документ ${index + 1}',
      );
      final requests = <({String path, String? key, Map body})>[];
      server.listen((request) async {
        requests.add((
          path: request.uri.path,
          key: request.headers.value('Authorization'),
          body: jsonDecode(await utf8.decoder.bind(request).join()) as Map,
        ));
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'tasks': [
                      for (final title in titles)
                        {
                          'quickAdd': title,
                          'description': 'Примечание к $title',
                          if (title == titles.first)
                            'subtasks': [
                              {'quickAdd': 'Сверить подпись'},
                            ],
                        },
                    ],
                  }),
                },
              },
            ],
          }),
        );
        await request.response.close();
      });
      final settings = _Settings(
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        smartModel: '',
      );
      final flow = _Flow(settings: settings);
      await HttpOverrides.runWithHttpOverrides(() async {
        await flow.open(database: db);
        await flow.model.setSmartMode(true);
        await pumpEventQueue();
        expect(flow.model.state.smartMode, isTrue);
        await flow.record();
      }, _LoopbackHttp());
      expect(flow.model.state.error, isNull);
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.path, '/v1/chat/completions');
      expect(request.key, 'Bearer fixture-key');
      expect(request.body['model'], 'fast-model');
      expect(
        (request.body['messages'] as List).last['content'],
        endsWith(_transcript),
      );
      expect(settings.keyReads, [settings.baseUrl]);
      final drafts = flow.model.state.drafts;
      expect(drafts.map((draft) => draft.quickAdd), titles);
      expect(await db.select(db.tasks).get(), isEmpty);
      final ids = await flow.model.save(drafts);
      final persisted = await db.select(db.tasks).get();
      expect(
        ids,
        hasLength(16),
      ); // 15 reviewed tasks plus one explicit subtask.
      expect(persisted.map((row) => row.id), unorderedEquals(ids!));
      final parents = persisted.where((row) => row.parentId == null);
      expect(parents.map((row) => row.content), unorderedEquals(titles));
      for (final row in parents) {
        expect(row.description, 'Примечание к ${row.content}');
      }
      expect(
        persisted
            .singleWhere((row) => row.content == 'Сверить подпись')
            .parentId,
        parents.singleWhere((row) => row.content == titles.first).id,
      );
      expect(flow.managed.transcripts, isEmpty);
      expect(flow.account.invokeFunctionCalls, isEmpty);
    },
  );

  for (final retry in [false, true]) {
    test(
      'a failed custom request retains text until explicit ${retry ? "retry" : "use as one task"}',
      () async {
        final flow = _Flow();
        await flow.open();
        flow.client.fail = true;
        await flow.record();
        expect(flow.model.state.error, ModelCheck.network);
        expect(flow.model.state.transcript, _transcript);
        expect(flow.model.state.drafts, isEmpty);
        expect(flow.client.requests, hasLength(1));
        expect(flow.saved, isEmpty);
        if (retry) {
          flow.client.fail = false;
          await flow.model.decomposeTranscript(flow.model.state.transcript);
          expect(flow.client.requests, hasLength(2));
          expect(flow.client.requests.last, flow.client.requests.first);
          expect(flow.model.state.drafts.single.quickAdd, 'Позвонить Анне');
        } else {
          flow.model.useTranscriptAsTask();
          expect(flow.client.requests, hasLength(1));
          expect(flow.model.state.drafts.single.quickAdd, _transcript);
          expect(flow.model.state.drafts.single.subtasks, isEmpty);
        }
        expect(flow.model.state.error, isNull);
        expect(flow.recognizer.starts, 1);
        expect(flow.managed.transcripts, isEmpty);
        expect(flow.account.invokeFunctionCalls, isEmpty);
      },
    );
  }
}

// Keep real loopback HTTP available inside the Flutter test binding.
class _LoopbackHttp extends HttpOverrides {}

class _UnusedFocusSoundPlayer extends Fake implements FocusSoundPlayer {}

class _Flow {
  _Flow({_Settings? settings}) : settings = settings ?? _Settings();
  final _Settings settings;
  final reviewed = Completer<void>();
  final account = FakeAccountClient()..currentUserIdValue = 'owner';
  final client = _Client();
  final managed = FakeTaskDecomposer();
  final recognizer = _Recognizer();
  final saved = <({List<DecomposedTaskDraft> drafts, String? project})>[];
  late VoiceQuickAddViewModel model;

  Future<void> open({AppDatabase? database}) async {
    final controller = VoiceRecognitionController(
      recordedRecognizer: recognizer,
      platformSupport: const VoicePlatformSupport(supportsRecordedSystem: true),
    );
    final preferences = LocalVoicePreferencesRepository(
      PreferencesService(() async => null),
      // A saved cloud preference must not send audio to the managed service.
      defaultMode: VoiceTranscriptionMode.cloud,
    );
    addTearDown(controller.dispose);
    addTearDown(preferences.dispose);
    final container = ProviderContainer(
      overrides: [
        accountSessionProvider.overrideWith(
          (_) => Stream.value((userId: 'owner', generation: 1)),
        ),
        accountClientProvider.overrideWithValue(account),
        billingAccessProvider.overrideWith(
          (_) => Stream.value((
            hasActiveEntitlement: false,
            hasLocalStoreKitEntitlement: false,
            loading: false,
          )),
        ),
        customModelGrantLoaderProvider.overrideWithValue(
          (_) async => (permanent: true, validUntil: null),
        ),
        customModelRepositoryProvider.overrideWithValue(settings),
        if (database == null)
          customVoiceAnalysisProvider.overrideWithValue(client.decompose)
        else ...[
          appDatabaseProvider.overrideWithValue(database),
          focusSoundPlayerProvider.overrideWithValue(_UnusedFocusSoundPlayer()),
          localSyncOwnerProvider.overrideWith((_) => Stream.value(null)),
        ],
        taskDecomposerProvider.overrideWithValue(managed),
        voicePreferencesRepositoryProvider.overrideWithValue(preferences),
        voiceRecognitionControllerProvider.overrideWithValue(controller),
        downloadableVoiceModelProvider.overrideWithValue(false),
        if (database == null)
          saveVoiceDraftsProvider.overrideWithValue((
            drafts, {
            defaultPriority,
            defaultDate,
            projectId,
            kanbanStatusId,
            labelId,
          }) async {
            saved.add((drafts: drafts, project: projectId));
            return ['saved-id'];
          }),
      ],
    );
    addTearDown(container.dispose);
    container.listen(accountSessionProvider, (_, _) {});
    container.listen(billingAccessProvider, (_, _) {});
    await container.read(accountSessionProvider.future);
    await container.read(billingAccessProvider.future);
    expect(
      await container.read(voiceAccessViewModelProvider.notifier).check(),
      isTrue,
    );
    final provider = voiceQuickAddViewModelProvider(Object());
    final listener = container.listen(provider, (previous, next) {
      if (previous?.analyzing == true &&
          !next.analyzing &&
          !reviewed.isCompleted) {
        reviewed.complete();
      }
    });
    addTearDown(listener.close);
    model = container.read(provider.notifier);
    model.setLocale('ru-RU');
    await model.restoreRecording();
    await pumpEventQueue();
    expect(model.state.customHost, Uri.parse(settings.baseUrl).authority);
    expect(model.state.transcriptionMode, VoiceTranscriptionMode.system);
    expect(model.state.cloudTranscriptionAvailable, isFalse);
  }

  Future<void> record() async {
    await model.start();
    await pumpEventQueue();
    expect(recognizer.starts, 1);
    expect(model.state.isCapturing, isTrue);
    expect(model.state.cloudMode, isFalse);
    expect(model.state.customHost, Uri.parse(settings.baseUrl).authority);
    await model.stop();
    await reviewed.future.timeout(const Duration(seconds: 5));
    await pumpEventQueue();
    expect(model.state.analyzing, isFalse);
    expect(managed.transcripts, isEmpty);
    expect(account.invokeFunctionCalls, isEmpty);
  }
}

class _Settings implements CustomModelRepository {
  _Settings({this.baseUrl = _base, this.smartModel = 'careful-model'});
  final String baseUrl;
  final String smartModel;
  final keyReads = <String>[];
  @override
  Future<CustomModelConfig> load() async => CustomModelConfig(
    enabled: true,
    baseUrl: baseUrl,
    normalModel: 'fast-model',
    smartModel: smartModel,
    hasKey: true,
  );
  @override
  Future<String> apiKeyFor(String baseUrl) async {
    keyReads.add(baseUrl);
    return 'fixture-key';
  }

  @override
  Future<CustomModelConfig> save(CustomModelConfig config, {String? apiKey}) =>
      throw UnimplementedError();
}

class _Recognizer extends RecordedVoiceRecognizer {
  int starts = 0;
  @override
  Future<void> start(VoiceRecognitionConfig config) async {
    starts++;
  }

  @override
  Future<VoiceRecognitionTranscript> stop(
    VoiceRecognitionConfig config,
  ) async => const VoiceRecognitionTranscript(text: _transcript);
  @override
  Future<void> cancel() async {}
  @override
  void dispose() {}
}

class _Client extends CustomModelClient {
  bool fail = false;
  final requests =
      <
        ({
          String url,
          String model,
          String key,
          String text,
          String locale,
          bool smart,
        })
      >[];
  @override
  Future<List<DecomposedTaskDraft>> decompose({
    required Uri baseUrl,
    required String model,
    required String apiKey,
    required String transcript,
    required DateTime now,
    required String locale,
    required bool smartMode,
  }) async {
    requests.add((
      url: baseUrl.toString(),
      model: model,
      key: apiKey,
      text: transcript,
      locale: locale,
      smart: smartMode,
    ));
    if (fail) {
      throw const CustomModelException(
        ModelCheck.network,
        'Connection unavailable',
      );
    }
    return [
      DecomposedTaskDraft(
        quickAdd: 'Позвонить Анне',
        description: 'Перед поездкой',
        subtasks: [DecomposedTaskDraft(quickAdd: 'Купить билеты')],
      ),
    ];
  }
}
