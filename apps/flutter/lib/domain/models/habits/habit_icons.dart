import 'package:pomodoist/domain/models/account/avatar_emoji.dart';

enum HabitIcon {
  bookOpen,
  dumbbell,
  footprints,
  glassWater,
  moon,
  sun,
  heart,
  brain,
  apple,
  coffee,
  music,
  pencil,
  code,
  leaf,
  target,
  bike,
}

/// Accept only catalog icons or one complete emoji at the editing boundary.
String? normalizeHabitIcon(String? input) {
  if (input == null) return null;
  final value = input.trim();
  if (value.runes.length > 32 ||
      !HabitIcon.values.any((icon) => icon.name == value) &&
          readAvatarEmoji(value) == null) {
    throw ArgumentError.value(input, 'icon', 'Expected a habit icon or emoji.');
  }
  return value;
}
