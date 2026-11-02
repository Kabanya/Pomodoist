import 'package:pomodoist/domain/models/app_flavor.dart';

const appIconBuildMode = bool.fromEnvironment('dart.vm.product')
    ? 'release'
    : bool.fromEnvironment('dart.vm.profile')
    ? 'profile'
    : 'debug';

String appIconDirectory(AppFlavor flavor, [String mode = appIconBuildMode]) =>
    'assets/branding/app_icons/generated/${flavor.name}${mode == 'release' ? '' : '/$mode'}';

enum AppIconChoice {
  pomo('icon-light-pomo'),
  classic('classic');

  const AppIconChoice(this.id);
  final String id;

  static AppIconChoice fromId(Object? value) =>
      value == classic.id ? classic : pomo;
}
