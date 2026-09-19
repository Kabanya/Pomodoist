import 'package:pomodoist/data/services/voice/voice_capture_service.dart';
import 'dart:async';

import 'package:app_voice/app_voice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/planning/task_decomposition_repository.dart';
import 'package:pomodoist/data/repositories/voice/voice_quick_add_repository.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/models/voice/voice_transcription_mode.dart';

void main() {
  test('voice repository ignores late decomposition after disposal', () async {
    final pending = Completer<List<DecomposedTaskDraft>>();
    final voice = _Voice();
    final repository = VoiceQuickAddRepository(
      initialController: AppVoiceCaptureService(voice),
      waitForMode: () async {},
      effectiveMode: () => VoiceTranscriptionMode.cloud,
      replaceController: () => AppVoiceCaptureService(voice),
      setMode: (_) async {},
      signedIn: () => true,
      preferences: () async => null,
      decomposer:
          (transcript, {required now, required locale, smartMode = false}) =>
              _Decomposer(pending.future).decompose(
                transcript,
                now: now,
                locale: locale,
                smartMode: smartMode,
              ),
    );
    var notifications = 0;
    repository.addListener(() => notifications++);
    final analysis = repository.decomposeTranscript('Plan the day');
    expect(repository.state.analyzing, isTrue);
    expect(notifications, 1);
    repository.dispose();
    pending.complete(const [DecomposedTaskDraft(quickAdd: 'Plan the day')]);
    (await analysis).getOrThrow();
    expect(notifications, 1);
    expect(repository.state.drafts, isEmpty);
  });
}

class _Decomposer implements TaskDecomposer {
  _Decomposer(this.pending);
  final Future<List<DecomposedTaskDraft>> pending;
  @override
  Future<List<DecomposedTaskDraft>> decompose(
    String transcript, {
    required DateTime now,
    required String locale,
    bool smartMode = false,
  }) => pending;
}

class _Voice implements VoiceRecognitionController {
  @override
  bool get canRetryTranscription => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
