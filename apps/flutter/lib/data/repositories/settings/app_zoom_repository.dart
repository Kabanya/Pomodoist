import 'package:pomodoist/utils/result.dart';

const appZoomPreferenceKey = 'app.zoomPercent';
const appZoomMinimum = 70;
const appZoomMaximum = 150;

/// Persisted interface zoom shared by every native window.
abstract interface class AppZoomRepository {
  Future<Result<int?>> read();
  Future<Result<void>> write(int percent);
}
