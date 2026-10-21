import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/ui/settings/view_models/app_icon_settings_view_model.dart';

class AppIconRuntime extends ConsumerWidget {
  const AppIconRuntime({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appIconSettingsProvider);
    return child;
  }
}
