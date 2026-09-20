import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/voice_dependencies.dart';
import 'package:pomodoist/config/voice_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/planning/task_decomposition_repository.dart';
import 'package:pomodoist/data/repositories/voice/voice_capture_repository.dart';
import 'package:pomodoist/data/repositories/voice/voice_preferences_repository_impl.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/account/account_session.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/models/voice/voice_capture_state.dart';
import 'package:pomodoist/domain/models/voice/voice_quick_add_state.dart';
import 'package:pomodoist/ui/voice/view_models/voice_quick_add_view_model.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'closing during capture cancels once and never publishes after close',
    () async {
      final capture = _FakeCaptureRepository();
      capture.emit(
        const VoiceCaptureState(
          status: VoiceCaptureStatus.recording,
          capturing: true,
          restoring: false,
        ),
      );
      final container = _container(capture: capture);
      final session = Object();
      final listener = container.listen(
        voiceQuickAddViewModelProvider(session),
        (_, _) {},
        fireImmediately: true,
      );
      final model = container.read(
        voiceQuickAddViewModelProvider(session).notifier,
      );
      expect(model.state.isCapturing, isTrue);
      expect(model.state.canStart, isFalse);

      expect(await model.closeVoice(), isTrue);
      expect(capture.closes, 1);
      await pumpEventQueue();
      expect(model.state.status, VoiceCaptureStatus.canceled);
      expect(model.state.isCapturing, isFalse);
      expect(model.state.canStart, isTrue);

      listener.close();
      container.dispose();
      expect(capture.closes, 1);
      expect(capture.stateSubscriptionCancels, 1);
    },
  );

  test('closing during transcription discards the active capture', () async {
    final capture = _FakeCaptureRepository();
    capture.emit(
      const VoiceCaptureState(
        status: VoiceCaptureStatus.transcribing,
        capturing: true,
        restoring: false,
      ),
    );
    final container = _container(capture: capture);
    addTearDown(container.dispose);
    final session = Object();
    final listener = container.listen(
      voiceQuickAddViewModelProvider(session),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    final model = container.read(
      voiceQuickAddViewModelProvider(session).notifier,
    );
    expect(model.state.isTranscribing, isTrue);
    expect(model.state.canStart, isFalse);

    expect(await model.closeVoice(), isTrue);
    expect(capture.closes, 1);
    await pumpEventQueue();
    expect(model.state.status, VoiceCaptureStatus.canceled);
    expect(model.state.isTranscribing, isFalse);
  });

  test('retry sends the locale and publishes the decomposed drafts', () async {
    final capture = _FakeCaptureRepository();
    final decomposer = _ControlledDecomposer();
    final container = _container(capture: capture, decomposer: decomposer);
    addTearDown(container.dispose);
    final session = Object();
    final listener = container.listen(
      voiceQuickAddViewModelProvider(session),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    final model = container.read(
      voiceQuickAddViewModelProvider(session).notifier,
    );
    model.setLocale('ru-RU');

    await model.start(retry: true);
    expect(capture.starts, ['ru-RU']);
    expect(capture.retries, [true]);
    capture.emit(
      const VoiceCaptureState(
        status: VoiceCaptureStatus.completed,
        transcript: 'Купить молоко',
        restoring: false,
      ),
    );
    await pumpEventQueue();
    expect(decomposer.requests, ['Купить молоко']);
    expect(decomposer.locales, ['ru-RU']);

    decomposer.complete([DecomposedTaskDraft(quickAdd: 'Купить молоко')]);
    await pumpEventQueue();
    expect(model.state.analyzing, isFalse);
    expect(model.state.drafts.single.quickAdd, 'Купить молоко');
    expect(model.state.canStart, isTrue);
  });

  test(
    'permission denial surfaces the capture failure and recovery target',
    () async {
      final capture = _FakeCaptureRepository();
      final container = _container(capture: capture);
      addTearDown(container.dispose);
      final session = Object();
      final listener = container.listen(
        voiceQuickAddViewModelProvider(session),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      final model = container.read(
        voiceQuickAddViewModelProvider(session).notifier,
      );

      capture.emit(
        const VoiceCaptureState(
          status: VoiceCaptureStatus.error,
          failure: VoiceCaptureFailure.microphoneDenied,
          voiceErrorCode: 'microphone_denied',
          settingsDestination: VoiceAccessSettings.microphone,
          restoring: false,
        ),
      );
      await pumpEventQueue();
      expect(model.state.error, VoiceQuickAddError.microphoneDenied);
      expect(model.state.voiceErrorCode, 'microphone_denied');
      expect(model.state.settingsDestination, VoiceAccessSettings.microphone);
      expect(model.state.canStart, isTrue);

      await model.recoverAccess();
      expect(capture.recoveryLocales, ['en']);
      await model.refreshAccess(request: true);
      expect(capture.refreshRequests, [(locale: 'en', request: true)]);

      capture.emit(
        const VoiceCaptureState(restoring: false, needsPermissionRequest: true),
      );
      await pumpEventQueue();
      expect(model.state.needsPermissionRequest, isTrue);
      expect(model.state.error, isNull);
    },
  );

  test(
    'a decomposition finishing after an account change is discarded',
    () async {
      final capture = _FakeCaptureRepository();
      final decomposer = _ControlledDecomposer();
      final sessions = StreamController<AccountSession>.broadcast();
      addTearDown(sessions.close);
      final container = _container(
        capture: capture,
        decomposer: decomposer,
        sessions: sessions.stream,
      );
      addTearDown(container.dispose);
      final session = Object();
      final listener = container.listen(
        voiceQuickAddViewModelProvider(session),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      sessions.add((userId: 'user-a', generation: 1));
      await pumpEventQueue();
      final model = container.read(
        voiceQuickAddViewModelProvider(session).notifier,
      );

      capture.emit(
        const VoiceCaptureState(
          status: VoiceCaptureStatus.completed,
          transcript: 'Plan the day',
          restoring: false,
        ),
      );
      await pumpEventQueue();
      expect(decomposer.requests, ['Plan the day']);

      sessions.add((userId: 'user-b', generation: 2));
      await pumpEventQueue();
      decomposer.complete([DecomposedTaskDraft(quickAdd: 'Plan the day')]);
      await pumpEventQueue();
      expect(model.state.drafts, isEmpty);
      expect(model.state.analyzing, isFalse);
      expect(model.state.transcript, 'Plan the day');
    },
  );

  test('a decomposition cannot publish after disposal', () async {
    final capture = _FakeCaptureRepository();
    final decomposer = _ControlledDecomposer();
    final container = _container(capture: capture, decomposer: decomposer);
    final session = Object();
    final states = <VoiceQuickAddState>[];
    final listener = container.listen(
      voiceQuickAddViewModelProvider(session),
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    container.read(voiceQuickAddViewModelProvider(session).notifier);

    capture.emit(
      const VoiceCaptureState(
        status: VoiceCaptureStatus.completed,
        transcript: 'Plan the day',
        restoring: false,
      ),
    );
    await pumpEventQueue();
    expect(decomposer.requests, hasLength(1));
    final published = states.length;

    listener.close();
    container.dispose();
    decomposer.complete([DecomposedTaskDraft(quickAdd: 'Plan the day')]);
    await pumpEventQueue();
    expect(states, hasLength(published));
    expect(states.last.analyzing, isTrue);
  });

  test(
    'drafts survive locale and smart-mode changes and stay independent per session',
    () async {
      final firstSession = Object();
      final secondSession = Object();
      final firstCapture = _FakeCaptureRepository();
      final secondCapture = _FakeCaptureRepository();
      final decomposer = _ControlledDecomposer();
      final preferences = LocalVoicePreferencesRepository(
        PreferencesService(() async => null),
      );
      final container = ProviderContainer(
        overrides: [
          voiceCaptureRepositoryProvider.overrideWith(
            (ref, session) =>
                identical(session, firstSession) ? firstCapture : secondCapture,
          ),
          taskDecomposerProvider.overrideWithValue(decomposer),
          voicePreferencesRepositoryProvider.overrideWithValue(preferences),
          accountSessionProvider.overrideWith(
            (ref) => Stream.value((userId: null, generation: 0)),
          ),
          saveVoiceDraftsProvider.overrideWithValue(_unexpectedSave),
        ],
      );
      addTearDown(container.dispose);
      final firstListener = container.listen(
        voiceQuickAddViewModelProvider(firstSession),
        (_, _) {},
        fireImmediately: true,
      );
      final secondListener = container.listen(
        voiceQuickAddViewModelProvider(secondSession),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(firstListener.close);
      addTearDown(secondListener.close);
      final first = container.read(
        voiceQuickAddViewModelProvider(firstSession).notifier,
      );
      final second = container.read(
        voiceQuickAddViewModelProvider(secondSession).notifier,
      );

      firstCapture.emit(
        const VoiceCaptureState(
          status: VoiceCaptureStatus.completed,
          transcript: 'First',
          restoring: false,
        ),
      );
      secondCapture.emit(
        const VoiceCaptureState(
          status: VoiceCaptureStatus.completed,
          transcript: 'Second',
          restoring: false,
        ),
      );
      await pumpEventQueue();
      expect(decomposer.requests, ['First', 'Second']);
      decomposer.complete([DecomposedTaskDraft(quickAdd: 'First')]);
      decomposer.complete([DecomposedTaskDraft(quickAdd: 'Second')], index: 1);
      await pumpEventQueue();
      expect(first.state.drafts.single.quickAdd, 'First');
      expect(second.state.drafts.single.quickAdd, 'Second');

      first.setLocale('ru-RU');
      first.setSmartMode(true);
      await pumpEventQueue();
      expect(first.state.drafts.single.quickAdd, 'First');
      expect(first.state.smartMode, isTrue);
      expect(second.state.drafts.single.quickAdd, 'Second');
      expect(second.state.smartMode, isTrue);
    },
  );

  test(
    'a duplicate submit writes once and a failed save keeps the drafts',
    () async {
      final capture = _FakeCaptureRepository();
      final decomposer = _ControlledDecomposer();
      final save = _ControlledSave();
      final container = _container(
        capture: capture,
        decomposer: decomposer,
        save: save.call,
      );
      addTearDown(container.dispose);
      final session = Object();
      final listener = container.listen(
        voiceQuickAddViewModelProvider(session),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      final model = container.read(
        voiceQuickAddViewModelProvider(session).notifier,
      );

      capture.emit(
        const VoiceCaptureState(
          status: VoiceCaptureStatus.completed,
          transcript: 'Buy milk',
          restoring: false,
        ),
      );
      await pumpEventQueue();
      decomposer.complete([DecomposedTaskDraft(quickAdd: 'Buy milk')]);
      await pumpEventQueue();
      expect(model.state.drafts, hasLength(1));

      final first = model.save(model.state.drafts);
      final duplicate = await model.save(model.state.drafts);
      expect(duplicate, isNull);
      expect(save.calls, hasLength(1));
      expect(model.state.saving, isTrue);

      save.pending.completeError(StateError('offline'));
      await expectLater(first, throwsA(isA<StateError>()));
      await pumpEventQueue();
      expect(model.state.saving, isFalse);
      expect(model.state.drafts.single.quickAdd, 'Buy milk');

      final retry = model.save(model.state.drafts);
      expect(save.calls, hasLength(2));
      save.pending.complete(const ['task-1']);
      expect(await retry, ['task-1']);
      await pumpEventQueue();
      expect(model.state.saving, isFalse);
    },
  );
}

ProviderContainer _container({
  required _FakeCaptureRepository capture,
  TaskDecomposer? decomposer,
  Stream<AccountSession>? sessions,
  SaveVoiceDrafts? save,
}) {
  return ProviderContainer(
    overrides: [
      voiceCaptureRepositoryProvider.overrideWith((ref, session) => capture),
      taskDecomposerProvider.overrideWithValue(
        decomposer ?? _ControlledDecomposer(),
      ),
      voicePreferencesRepositoryProvider.overrideWithValue(
        LocalVoicePreferencesRepository(PreferencesService(() async => null)),
      ),
      accountSessionProvider.overrideWith(
        (ref) => sessions ?? Stream.value((userId: null, generation: 0)),
      ),
      saveVoiceDraftsProvider.overrideWithValue(save ?? _unexpectedSave),
    ],
  );
}

Future<List<String>> _unexpectedSave(
  List<DecomposedTaskDraft> drafts, {
  int? defaultPriority,
  DateTime? defaultDate,
  String? projectId,
  String? kanbanStatusId,
  String? labelId,
}) async => throw StateError('Unexpected save');

class _FakeCaptureRepository implements VoiceCaptureRepository {
  VoiceCaptureState _state = const VoiceCaptureState(restoring: false);
  final _states = StreamController<VoiceCaptureState>.broadcast();
  final starts = <String>[];
  final retries = <bool>[];
  final recoveryLocales = <String>[];
  final refreshRequests = <({String locale, bool request})>[];
  int closes = 0;
  int stops = 0;
  int restores = 0;
  int stateSubscriptionCancels = 0;

  @override
  VoiceCaptureState get currentState => _state;

  @override
  Stream<VoiceCaptureState> watchState() {
    final controller = StreamController<VoiceCaptureState>();
    controller.add(_state);
    final subscription = _states.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = () {
      stateSubscriptionCancels++;
      subscription.cancel();
    };
    return controller.stream;
  }

  void emit(VoiceCaptureState state) {
    _state = state;
    _states.add(state);
  }

  @override
  Future<Result<void>> start(String locale, {bool retry = false}) async {
    starts.add(locale);
    retries.add(retry);
    emit(
      VoiceCaptureState(
        status: retry
            ? VoiceCaptureStatus.transcribing
            : VoiceCaptureStatus.requestingPermission,
        capturing: true,
        restoring: false,
      ),
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> stop() async {
    stops++;
    return const Success(null);
  }

  @override
  Future<Result<bool>> close() async {
    closes++;
    emit(
      VoiceCaptureState(
        status: VoiceCaptureStatus.canceled,
        transcript: _state.transcript,
        restoring: false,
      ),
    );
    return const Success(true);
  }

  @override
  Future<Result<void>> restore() async {
    restores++;
    emit(const VoiceCaptureState(restoring: false));
    return const Success(null);
  }

  @override
  Future<Result<void>> refreshAccess({
    required String locale,
    bool request = false,
  }) async {
    refreshRequests.add((locale: locale, request: request));
    return const Success(null);
  }

  @override
  Future<Result<void>> recoverAccess(String locale) async {
    recoveryLocales.add(locale);
    return const Success(null);
  }

  @override
  Future<Result<void>> useCloudTranscription(String locale) async =>
      const Success(null);
}

class _ControlledDecomposer implements TaskDecomposer {
  final requests = <String>[];
  final locales = <String>[];
  final smartModes = <bool>[];
  final _pending = <Completer<List<DecomposedTaskDraft>>>[];

  @override
  Future<List<DecomposedTaskDraft>> decompose(
    String transcript, {
    required DateTime now,
    required String locale,
    bool smartMode = false,
  }) {
    requests.add(transcript);
    locales.add(locale);
    smartModes.add(smartMode);
    final completer = Completer<List<DecomposedTaskDraft>>();
    _pending.add(completer);
    return completer.future;
  }

  void complete(List<DecomposedTaskDraft> drafts, {int index = 0}) =>
      _pending[index].complete(drafts);
}

class _ControlledSave {
  final calls = <List<DecomposedTaskDraft>>[];
  late Completer<List<String>> pending;

  Future<List<String>> call(
    List<DecomposedTaskDraft> drafts, {
    int? defaultPriority,
    DateTime? defaultDate,
    String? projectId,
    String? kanbanStatusId,
    String? labelId,
  }) {
    calls.add(List.unmodifiable(drafts));
    pending = Completer<List<String>>();
    return pending.future;
  }
}
