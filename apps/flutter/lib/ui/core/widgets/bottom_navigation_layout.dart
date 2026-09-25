import 'package:pomodoist/domain/models/settings/bottom_navigation_preferences.dart';

({bool expands, bool labelsBelow}) bottomNavigationLayout(
  BottomNavigationStyle style,
  int count,
) => (
  expands: count > 0 && (style == BottomNavigationStyle.labels || count >= 4),
  labelsBelow: style == BottomNavigationStyle.labels && count >= 3,
);
