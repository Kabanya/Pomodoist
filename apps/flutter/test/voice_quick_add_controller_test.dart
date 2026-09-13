import 'dart:async';

import 'package:app_voice/app_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/planning/data/task_decomposer.dart';
import 'package:pomodoist/features/voice/application/voice_quick_add_controller.dart';
import 'package:pomodoist/features/voice/data/voice_transcription_mode.dart';
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
      controller.status = VoiceRecognitionStatus.recording;
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
      closing.status = VoiceRecognitionStatus.transcribing;
      expect(await closing.closeVoice(), isTrue);
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

VoiceQuickAddController _controller(
  _Voice voice, {
  Future<void> Function()? waitForMode,
  VoiceRecognitionController Function()? replace,
  Future<SharedPreferences?> Function()? preferences,
  TaskDecomposer? decomposer,
  void Function(List<DecomposedTaskDraft>)? onDrafts,
}) => VoiceQuickAddController(
  initialController: voice,
  waitForMode: waitForMode ?? () async {},
  effectiveMode: () => VoiceTranscriptionMode.cloud,
  replaceController: replace ?? () => voice,
  setMode: (_) async {},
  signedIn: () => true,
  preferences: preferences ?? () async => null,
  decomposer: () => decomposer ?? (throw StateError('Unexpected analysis')),
  locale: () => 'en',
  onDrafts: onDrafts ?? (_) {},
  onAnalysisStart: () {},
  onAnalysisFinish: () async {},
);

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
