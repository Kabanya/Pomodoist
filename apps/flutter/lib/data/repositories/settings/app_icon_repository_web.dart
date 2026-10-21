import 'dart:js_interop';

import 'package:pomodoist/data/repositories/settings/app_icon_repository.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';
import 'package:pomodoist/domain/models/settings/app_icon_choice.dart';

@JS('pomodoistSetAppIcon')
external void _setIcon(JSString icon, JSString flavor);

class PlatformAppIconRepository implements AppIconRepository {
  AppIconChoice _current = AppIconChoice.pomo;

  @override
  Future<AppIconChoice> read() async => _current;

  @override
  Future<void> apply(AppIconChoice choice) async {
    _setIcon(choice.id.toJS, appFlavor.name.toJS);
    _current = choice;
  }
}
