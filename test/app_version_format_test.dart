import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/settings/presentation/app_info_card.dart';

void main() {
  test('formatAppVersion includes a non-empty build number', () {
    expect(formatAppVersion('2.4.1', '37'), '2.4.1 (37)');
  });

  test('formatAppVersion omits an empty build number', () {
    expect(formatAppVersion('2.4.1', ''), '2.4.1');
  });
}
