import 'package:flutter/widgets.dart';

import 'update_contracts.dart';

/// Updater copy is kept together because the IO adapter is also compiled on
/// platforms that do not expose this UI. Fallback follows the app's English UI.
class UpdateCopy {
  const UpdateCopy(this.ru);
  factory UpdateCopy.of(BuildContext context) =>
      UpdateCopy(Localizations.localeOf(context).languageCode == 'ru');
  final bool ru;
  String get title => ru ? 'Обновление Pomodoist' : 'Pomodoist update';
  String get update => ru ? 'Обновить' : 'Update';
  String get close => ru ? 'Закрыть' : 'Close';
  String get check => ru ? 'Проверить обновления' : 'Check for updates';
  String get settings => ru ? 'Обновления' : 'Updates';
  String get rc => ru ? 'Получать релиз-кандидаты (RC)' : 'Receive release candidates (RC)';
  String get stable => ru ? 'Канал: стабильные релизы' : 'Channel: stable releases';
  String get rcChannel => ru ? 'Канал: стабильные релизы и RC' : 'Channel: stable releases and RC';
  String get rcHelp => ru ? 'RC могут содержать ошибки. Альфа- и бета-версии исключены.'
      : 'RC releases may contain bugs. Alpha and beta versions are excluded.';
  String get restart => ru ? 'Приложение перезапустится. Ваши данные сохранятся.'
      : 'The app will restart. Your data will be preserved.';
  String get notes => ru ? 'Все изменения' : 'Release notes';
  String get ownerManaged => ru ? 'Эту сборку обновляет её владелец, чтобы сохранить настройки сервера. Запросите у него последнюю версию.'
      : 'This build is updated by its owner to preserve its server configuration. Ask them for the latest version.';
  String get unsupported => ru ? 'Автообновление доступно в официальной Linux AppImage. Другие сборки обновляйте через менеджер пакетов.'
      : 'Automatic updates are available in the official Linux AppImage. Use your package manager for other builds.';
  String version(String value) => ru ? 'Версия $value' : 'Version $value';
  String phase(UpdatePhase value) => switch (value) {
    UpdatePhase.idle => ru ? 'Проверка доступна в любое время.' : 'You can check at any time.',
    UpdatePhase.checking => ru ? 'Проверяем релизы…' : 'Checking releases…',
    UpdatePhase.available => ru ? 'Доступна новая версия' : 'A new version is available',
    UpdatePhase.downloading => ru ? 'Скачиваем обновление…' : 'Downloading update…',
    UpdatePhase.verifying => ru ? 'Проверяем целостность…' : 'Verifying integrity…',
    UpdatePhase.installing => ru ? 'Подготавливаем установку и перезапуск…' : 'Preparing installation and restart…',
    UpdatePhase.upToDate => ru ? 'Установлена последняя подходящая версия.' : 'You have the latest compatible version.',
    UpdatePhase.failed => ru ? 'Не удалось обновить приложение' : 'The update could not be completed',
  };
}
