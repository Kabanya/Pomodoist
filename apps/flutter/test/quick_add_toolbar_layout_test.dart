import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_toolbar_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final theme = AppTheme.shadFromMaterial(AppTheme.light());
  double width(String label, {double scale = 1, double trailing = 0}) =>
      quickAddLabeledButtonWidth(
        label,
        theme: theme,
        textScaler: TextScaler.linear(scale),
        textDirection: TextDirection.ltr,
        trailingWidth: trailing,
      );

  test('long labels and text scaling consume their real additional width', () {
    expect(width('A long project name'), greaterThan(width('Inbox')));
    expect(width('Inbox', scale: 2), greaterThan(width('Inbox')));
    expect(width('Inbox', trailing: 12) - width('Inbox'), 20);
  });

  test('compact mode starts only when the whole labeled row would wrap', () {
    final requiredWidth =
        [
          width('No date', trailing: 12),
          width('Inbox', trailing: 12),
          width('P4', trailing: 12),
          width('Pomodoro estimate'),
          width('Comment'),
          width('Add'),
        ].reduce((a, b) => a + b) +
        5 * 8;
    expect(quickAddToolbarUsesIcons(requiredWidth, requiredWidth), isFalse);
    expect(quickAddToolbarUsesIcons(requiredWidth - .1, requiredWidth), isTrue);
    expect(quickAddToolbarUsesIcons(700, 650), isFalse);
    expect(quickAddToolbarUsesIcons(850, 900), isTrue);
  });
}
