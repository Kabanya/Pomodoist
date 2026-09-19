import 'package:pomodoist/data/services/voice/voice_capture_service.dart';
import 'package:pomodoist/data/services/voice/voice_transcription_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/voice/voice_quick_add_repository.dart';
import 'package:pomodoist/config/voice_preferences_dependencies.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/use_cases/quick_add/voice_quick_add_use_case.dart';

final voiceQuickAddRepositoryProvider = Provider.autoDispose
    .family<VoiceQuickAddRepository, Object>((ref, session) {
      final repository = VoiceQuickAddRepository(
        initialController: AppVoiceCaptureService(
          ref.read(voiceRecognitionControllerProvider),
        ),
        waitForMode: () => ref
            .read(voicePreferencesRepositoryProvider)
            .ready
            .then((result) => result.getOrThrow()),
        effectiveMode: () => effectiveVoiceTranscriptionMode(
          isWeb: kIsWeb,
          platform: defaultTargetPlatform,
          preferred: ref.read(voiceTranscriptionModeProvider),
          signedIn: ref.read(accountClientProvider)?.currentUserId != null,
        ),
        replaceController: () {
          ref.invalidate(voiceRecognitionControllerProvider);
          return AppVoiceCaptureService(
            ref.read(voiceRecognitionControllerProvider),
          );
        },
        setMode: (mode) => ref
            .read(voicePreferencesRepositoryProvider)
            .setMode(mode)
            .then((result) => result.getOrThrow()),
        signedIn: () => ref.read(accountClientProvider)?.currentUserId != null,
        preferences: () => ref.read(sharedPreferencesProvider.future),
        decomposer:
            (transcript, {required now, required locale, smartMode = false}) =>
                ref
                    .read(taskDecomposerProvider)
                    .decompose(
                      transcript,
                      now: now,
                      locale: locale,
                      smartMode: smartMode,
                    ),
      );
      ref.onDispose(repository.dispose);
      return repository;
    });
typedef SaveVoiceDrafts =
    Future<List<String>> Function(
      List<DecomposedTaskDraft> drafts, {
      int? defaultPriority,
      DateTime? defaultDate,
      String? projectId,
      String? kanbanStatusId,
      String? labelId,
    });
final saveVoiceDraftsProvider = Provider<SaveVoiceDrafts>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final quickAdd = ref.watch(quickAddServiceProvider);
  return (
    drafts, {
    defaultPriority,
    defaultDate,
    projectId,
    kanbanStatusId,
    labelId,
  }) => db.transaction(
    () => createVoiceQuickAddTasks(
      quickAdd,
      drafts,
      defaultPriority: defaultPriority,
      defaultDate: defaultDate,
      projectId: projectId,
      kanbanStatusId: kanbanStatusId,
      labelId: labelId,
    ),
  );
});
