import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/app_zoom_repository.dart';
import 'package:pomodoist/data/repositories/settings/app_zoom_repository_impl.dart';

final appZoomRepositoryProvider = Provider<AppZoomRepository>(
  (ref) => LocalAppZoomRepository(ref.watch(preferencesServiceProvider)),
);
