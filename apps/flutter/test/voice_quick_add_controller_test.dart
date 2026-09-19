import 'package:pomodoist/data/services/voice/voice_capture_service.dart';
import 'package:pomodoist/domain/models/voice/voice_quick_add_state.dart';
import 'package:pomodoist/data/repositories/planning/remote_task_decomposer.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/data/repositories/planning/task_decomposition_repository.dart';
import 'dart:async';

import 'package:app_voice/app_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/voice/voice_quick_add_repository.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'restore waits for saved mode and replaces without discarding audio',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final ready = Completer<void>();
      final original = _Voice();
      final replacement = _Voice();
      var replacements = 0;
      final controller = _controller(
        original,
        waitForMode: () => ready.future,
        replace: () {
          replacements++;
          return replacement;
        },
      );
      addTearDown(controller.dispose);
      final restored = controller.restoreRecording();
      expect(controller.canStart, isFalse);
      expect(replacements, 0);
      ready.complete();
      await restored;
      expect(replacements, 1);
      expect(original.cancels, 0);
      expect(replacement.restores, 1);
      expect(controller.canStart, isTrue);
    },
  );

  test(
    'stop is single-flight and disposal aborts while explicit close discards',
    () async {
      final voice = _Voice();
      final stopped = Completer<void>();
      voice.stopped = stopped.future;
      final controller = _controller(voice);
      controller.status = VoiceCaptureStatus.recording;
      controller.captureActive = true;
      final first = controller.stop();
      await controller.stop();
      expect(voice.stops, 1);
      controller.dispose();
      expect(voice.aborts, 1);
      expect(voice.cancels, 0);
      stopped.complete();
      await first;

      final discarded = _Voice();
      final closing = _controller(discarded);
      closing.status = VoiceCaptureStatus.transcribing;
      expect((await closing.closeVoice()).getOrThrow(), isTrue);
      closing.dispose();
      expect(discarded.cancels, 1);
      expect(discarded.aborts, 0);
    },
  );

  test(
    'smart preference loading preserves an explicit choice and manual analysis retries',
    () async {
      SharedPreferences.setMockInitialValues({'voice.smartMode': false});
      final prefs = Completer<SharedPreferences?>();
      final smartValues = <bool>[];
      final transcripts = <String>[];
      var drafts = <DecomposedTaskDraft>[];
      final controller = _controller(
        _Voice(),
        preferences: () => prefs.future,
        decomposer: SupabaseTaskDecomposer(
          transport: (body) async {
            final command = body['command']! as Map;
            smartValues.add(command['smart'] as bool);
            transcripts.add(command['transcript'] as String);
            if (smartValues.length == 1) {
              throw const TaskDecompositionException('Retry');
            }
            return {
              'ok': true,
              'tasks': [
                {
                  'quickAdd': 'Edited parent',
                  'subtasks': [
                    {'quickAdd': 'Child'},
                  ],
                },
              ],
            };
          },
        ),
        onDrafts: (value) => drafts = value,
      );
      addTearDown(controller.dispose);
      final loading = controller.loadSmartMode();
      controller.setSmartMode(true);
      prefs.complete(await SharedPreferences.getInstance());
      await loading;
      expect(controller.smartMode, isTrue);
      controller.transcript = 'Original transcript';
      await controller.decomposeTranscript(controller.transcript);
      expect(drafts.single.quickAdd, 'Original transcript');
      expect(controller.error, 'Retry');
      await controller.decomposeTranscript(controller.transcript);
      expect(controller.error, isNull);
      expect(drafts.single.subtasks.single.quickAdd, 'Child');
      expect(transcripts, ['Original transcript', 'Original transcript']);
      expect(smartValues, [true, true]);
    },
  );
}

VoiceQuickAddRepository _controller(
  _Voice voice, {
  Future<void> Function()? waitForMode,
  VoiceRecognitionController Function()? replace,
  Future<SharedPreferences?> Function()? preferences,
  TaskDecomposer? decomposer,
  void Function(List<DecomposedTaskDraft>)? onDrafts,
}) {
  final repository = VoiceQuickAddRepository(
    initialController: AppVoiceCaptureService(voice),
    waitForMode: waitForMode ?? () async {},
    effectiveMode: () => VoiceTranscriptionMode.cloud,
    replaceController: () => AppVoiceCaptureService((replace ?? () => voice)()),
    setMode: (_) async {},
    signedIn: () => true,
    preferences: preferences ?? () async => null,
    decomposer:
        (transcript, {required now, required locale, smartMode = false}) =>
            (decomposer ?? (throw StateError('Unexpected analysis'))).decompose(
              transcript,
              now: now,
              locale: locale,
              smartMode: smartMode,
            ),
  );
  if (onDrafts != null) {
    repository.addListener(() => onDrafts(repository.drafts));
  }
  return repository;
}

class _Voice implements VoiceRecognitionController {
  int cancels = 0;
  int aborts = 0;
  int stops = 0;
  int restores = 0;
  Future<void>? stopped;
  @override
  bool get canRetryTranscription => false;
  @override
  Future<bool> restorePendingRecording() async {
    restores++;
    return false;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<void> abortTranscription() async {
    aborts++;
  }

  @override
  Future<void> stop() {
    stops++;
    return stopped ?? Future.value();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
