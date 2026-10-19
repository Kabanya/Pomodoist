import 'package:pomodoist/domain/models/focus/focus_sound_set.dart';

abstract interface class FocusSoundPreviewPlayer {
  Future<void> preview(FocusSoundSet soundSet);
  Future<void> stop();
  Future<void> dispose();
}
