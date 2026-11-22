/// Device-local task analysis settings. The API key is stored separately.
class CustomModelConfig {
  const CustomModelConfig({
    this.enabled = false,
    this.baseUrl = '',
    this.normalModel = '',
    this.smartModel = '',
    this.hasKey = false,
  });

  final bool enabled;
  final String baseUrl;
  final String normalModel;
  final String smartModel;
  final bool hasKey;

  CustomModelConfig withEnabled(bool value) => CustomModelConfig(
    enabled: value,
    baseUrl: baseUrl,
    normalModel: normalModel,
    smartModel: smartModel,
    hasKey: hasKey,
  );
}

enum ModelCheck {
  success,
  configuration,
  unauthorized,
  rateLimited,
  provider,
  network,
  timeout,
  invalidResponse,
}

class CustomModelException implements Exception {
  const CustomModelException(this.code, this.message)
    : assert(code != ModelCheck.success);
  final ModelCheck code;
  final String message;

  @override
  String toString() => message;
}
