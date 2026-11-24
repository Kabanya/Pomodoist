import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/custom_model_access.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/custom_model_repository.dart';
import 'package:pomodoist/data/repositories/settings/custom_model_repository_impl.dart';
import 'package:pomodoist/data/services/local/custom_model_key_store.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/data/services/planning/custom_model_client.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';
import 'package:pomodoist/domain/models/settings/custom_model_config.dart';

final customModelOwnerProvider = Provider<String?>((ref) {
  ref.watch(accountSessionProvider);
  return ref.watch(accountSessionRepositoryProvider).currentSession.userId;
});

final _keyStore = Provider((ref) => CustomModelKeyStore());

final customModelRepositoryProvider = Provider<CustomModelRepository>((ref) {
  final owner = ref.watch(customModelOwnerProvider);
  final prefs = ref.watch(sharedPreferencesProvider.future);
  return StoredCustomModelRepository(
    PreferencesService(() async {
      return await prefs ?? (throw StateError('Preferences unavailable.'));
    }),
    ref.watch(_keyStore),
    '${appFlavor.applicationId}.${owner == null ? "device" : "user.$owner"}',
  );
});

String normalizedCustomModelUrl(String value) =>
    CustomModelClient.parseBaseUrl(value).toString();

typedef ModelProbe =
    Future<ModelCheck> Function({
      required String baseUrl,
      required String model,
      required String apiKey,
      required String locale,
      required bool smart,
    });

final customModelProbeProvider = Provider<ModelProbe>((ref) {
  return ({
    required baseUrl,
    required model,
    required apiKey,
    required locale,
    required smart,
  }) async {
    try {
      await const CustomModelClient().decompose(
        baseUrl: CustomModelClient.parseBaseUrl(baseUrl),
        model: model,
        apiKey: apiKey,
        locale: locale,
        transcript: 'Buy a notebook tomorrow.',
        now: DateTime.now(),
        smartMode: smart,
      );
      return ModelCheck.success;
    } on CustomModelException catch (e) {
      return e.code;
    }
  };
});

final customModelConfigProvider =
    AsyncNotifierProvider<CustomModelSettings, CustomModelConfig>(
      CustomModelSettings.new,
    );

class CustomModelSettings extends AsyncNotifier<CustomModelConfig> {
  @override
  Future<CustomModelConfig> build() =>
      ref.watch(customModelRepositoryProvider).load();

  String normalizeUrl(String input) => normalizedCustomModelUrl(input);

  Future<void> _requireAccess(CustomModelRepository repository) async {
    if (!await ref.read(customModelAccessProvider.future) ||
        !ref.mounted ||
        repository != ref.read(customModelRepositoryProvider)) {
      throw StateError('Custom model access unavailable.');
    }
  }

  Future<CustomModelConfig> save(
    CustomModelConfig config, {
    String? apiKey,
    String? expectedVersion,
  }) async {
    final repository = ref.read(customModelRepositoryProvider);
    await _requireAccess(repository);
    final updated = await repository.save(
      config,
      apiKey: apiKey,
      expectedVersion: expectedVersion,
    );
    if (ref.mounted && repository == ref.read(customModelRepositoryProvider)) {
      state = AsyncData(updated);
    }
    return updated;
  }

  Future<Map<String, ModelCheck>> check(
    CustomModelConfig config, {
    required String locale,
    String? apiKey,
  }) async {
    final repository = ref.read(customModelRepositoryProvider);
    await _requireAccess(repository);
    final url = normalizeUrl(config.baseUrl);
    final key = apiKey ?? await repository.apiKeyFor(url);
    final probe = ref.read(customModelProbeProvider);
    final results = <String, ModelCheck>{};
    for (final model in {
      config.normalModel.trim(),
      config.smartModel.trim(),
    }..remove('')) {
      await _requireAccess(repository);
      results[model] = await probe(
        baseUrl: url,
        model: model,
        apiKey: key,
        locale: locale,
        smart: model != config.normalModel.trim(),
      );
    }
    return results;
  }
}
