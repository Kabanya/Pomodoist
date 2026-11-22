import 'package:pomodoist/domain/models/settings/custom_model_config.dart';

abstract interface class CustomModelRepository {
  Future<CustomModelConfig> load();
  Future<String> apiKeyFor(String baseUrl);

  /// An omitted key retains the credential only when the base URL is unchanged.
  Future<CustomModelConfig> save(CustomModelConfig config, {String? apiKey});
}
