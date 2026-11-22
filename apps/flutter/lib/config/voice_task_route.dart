import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/billing_dependencies.dart';
import 'package:pomodoist/config/custom_model_settings_dependencies.dart';
import 'package:pomodoist/data/services/planning/custom_model_client.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';

/// The destination shown when recording begins, including the selected model.
/// Never store a provider credential in a recording or a task draft.
typedef VoiceTaskTarget = ({String baseUrl, String model});
const managedVoiceTarget = (baseUrl: '', model: '');

final voiceTaskTargetProvider = FutureProvider.family<VoiceTaskTarget, bool>((
  ref,
  smart,
) async {
  final config = await ref.watch(customModelConfigProvider.future);
  if (!config.enabled) return managedVoiceTarget;
  return (
    baseUrl: CustomModelClient.parseBaseUrl(config.baseUrl).toString(),
    model: smart && config.smartModel.trim().isNotEmpty
        ? config.smartModel.trim()
        : config.normalModel.trim(),
  );
});

typedef CustomVoiceAnalysis =
    Future<List<DecomposedTaskDraft>> Function({
      required Uri baseUrl,
      required String model,
      required String apiKey,
      required String transcript,
      required DateTime now,
      required String locale,
      required bool smartMode,
    });
final customVoiceAnalysisProvider = Provider<CustomVoiceAnalysis>(
  (ref) => const CustomModelClient().decompose,
);

final voiceApiKeyProvider = Provider(
  (ref) =>
      (String url) => ref.read(customModelRepositoryProvider).apiKeyFor(url),
);

final managedVoiceAccessProvider = Provider<bool>((ref) {
  final access = ref.watch(billingAccessProvider);
  return access.asData?.value.hasActiveEntitlement ?? false;
});
