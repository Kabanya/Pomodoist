import 'package:app_voice/app_voice.dart';
import 'package:pomodoist/data/repositories/voice/captured_voice_repository.dart';
import 'package:pomodoist/data/repositories/voice/voice_capture_repository.dart';
import 'package:pomodoist/data/services/voice/pomodoist_voice_controller.dart';
import 'package:pomodoist/data/services/voice/voice_capture_service.dart';
import 'package:pomodoist/data/services/voice/voice_transcription_policy.dart';
import 'package:pomodoist/data/services/voice/account_voice_backend.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/voice_preferences_dependencies.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/use_cases/quick_add/voice_quick_add_use_case.dart';

/// The recognizer handle for the current account. Composition keeps a live
/// account reference without rebuilding an active recording on bootstrap or
/// token changes; disposal must not access an already-disposed Ref.
final voiceRecognitionControllerProvider = Provider<VoiceRecognitionController>(
  (ref) {
    var account = ref.read(accountClientProvider);
    ref.listen(accountClientProvider, (_, next) {
      account = next;
    });
    final backend = AccountVoiceBackend(() => account);
    final controller = createPomodoistVoiceController(
      mode: effectiveVoiceTranscriptionMode(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
        preferred: ref.read(voiceTranscriptionModeProvider),
        signedIn: account?.currentUserId != null,
      ),
      ownerId: () => account?.currentUserId,
      invoke: backend.call,
    );
    ref.onDispose(() {
      backend.dispose();
      controller.dispose();
    });
    return controller;
  },
);

final voiceCaptureRepositoryProvider = Provider.autoDispose
    .family<VoiceCaptureRepository, Object>((ref, session) {
      final repository = CapturedVoiceRepository(
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
  final useCase = VoiceQuickAddUseCase(
    quickAdd: ref.watch(quickAddUseCaseProvider),
    runLocalTransaction: ref.watch(localTransactionProvider),
    hints: ref.watch(quickAddHintRepositoryProvider),
  );
  return (
    drafts, {
    defaultPriority,
    defaultDate,
    projectId,
    kanbanStatusId,
    labelId,
  }) => useCase(
    drafts,
    defaultPriority: defaultPriority,
    defaultDate: defaultDate,
    projectId: projectId,
    kanbanStatusId: kanbanStatusId,
    labelId: labelId,
  );
});
