import 'dart:convert';
import 'package:pomodoist/data/repositories/settings/custom_model_repository.dart';
import 'package:pomodoist/data/services/local/custom_model_key_store.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/data/services/planning/custom_model_client.dart';
import 'package:pomodoist/domain/models/settings/custom_model_config.dart';

class StoredCustomModelRepository implements CustomModelRepository {
  StoredCustomModelRepository(this._preferences, this._keys, this._scope);

  final PreferencesService _preferences;
  final CustomModelKeyStore _keys;
  final String _scope;
  String get _settings => 'customModel.v1.$_scope';
  String get _credential => '$_settings.credential';
  Future<void> _pending = Future.value();

  @override
  Future<CustomModelConfig> load() async {
    final values = (await _preferences.read([_settings])).getOrThrow();
    if (values[_settings] case final String raw) {
      final json = jsonDecode(raw) as Map;
      return CustomModelConfig(
        enabled: json['enabled'] == true,
        baseUrl: json['baseUrl'] as String,
        normalModel: json['normalModel'] as String,
        smartModel: json['smartModel'] as String,
        hasKey:
            json['hasKey'] == true &&
            (!_keys.sessionOnly || await _keys.read(_credential) != null),
      );
    }
    return const CustomModelConfig();
  }

  @override
  Future<String> apiKeyFor(String baseUrl) async {
    final config = await load();
    if (!config.hasKey || config.baseUrl != baseUrl) return '';
    final raw = await _keys.read(_credential);
    if (raw == null) return '';
    final key = jsonDecode(raw) as Map;
    return key['baseUrl'] == baseUrl ? key['value'] as String : '';
  }

  @override
  Future<CustomModelConfig> save(CustomModelConfig config, {String? apiKey}) {
    final operation = _pending.then((_) => _save(config, apiKey));
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<CustomModelConfig> _save(
    CustomModelConfig config,
    String? apiKey,
  ) async {
    final old = await load();
    final url = config.enabled || config.baseUrl.isNotEmpty
        ? CustomModelClient.parseBaseUrl(config.baseUrl).toString()
        : '';
    final normal = config.normalModel.trim();
    if (config.enabled && normal.isEmpty) {
      throw const FormatException('Missing model.');
    }
    final key = apiKey?.trim();
    if (key != null && key.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('Invalid key.');
    }
    final sameEndpoint = old.baseUrl == url;
    final hasKey = key == null ? sameEndpoint && old.hasKey : key.isNotEmpty;
    final replaceKey =
        (key?.isNotEmpty ?? false) ||
        old.hasKey && (!sameEndpoint || key != null);
    final previous = replaceKey && old.hasKey
        ? await _keys.read(_credential)
        : null;
    if (replaceKey) {
      await _keys.write(
        _credential,
        hasKey ? jsonEncode({'baseUrl': url, 'value': key}) : null,
      );
    }
    try {
      (await _preferences.write({
        _settings: jsonEncode({
          'enabled': config.enabled,
          'baseUrl': url,
          'normalModel': normal,
          'smartModel': config.smartModel.trim(),
          'hasKey': hasKey,
        }),
      })).getOrThrow();
    } catch (_) {
      if (replaceKey) await _keys.write(_credential, previous);
      rethrow;
    }
    return CustomModelConfig(
      enabled: config.enabled,
      baseUrl: url,
      normalModel: normal,
      smartModel: config.smartModel.trim(),
      hasKey: hasKey,
    );
  }
}
