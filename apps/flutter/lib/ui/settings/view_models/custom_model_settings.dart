import 'package:pomodoist/config/custom_model_settings_dependencies.dart';

export 'package:pomodoist/config/custom_model_access.dart'
    show customModelAccessProvider;
export 'package:pomodoist/config/custom_model_settings_dependencies.dart'
    show customModelOwnerProvider;
export 'package:pomodoist/domain/models/settings/custom_model_config.dart';

final customModelSettingsProvider = customModelConfigProvider;
