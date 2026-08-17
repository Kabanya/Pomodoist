import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Linux runner forwards deep links to the primary GTK application', () {
    final source = File('linux/runner/my_application.cc').readAsStringSync();

    expect(source, contains('G_APPLICATION_HANDLES_COMMAND_LINE'));
    expect(source, contains('G_APPLICATION_HANDLES_OPEN'));
    expect(source, isNot(contains('G_APPLICATION_NON_UNIQUE')));
    expect(source, contains('gtk_application_get_windows'));
    expect(source, contains('gtk_window_present'));
    expect(source, contains('g_application_register(application'));
    expect(
      source,
      contains(
        'g_application_activate(application);\n  *exit_status = 0;\n\n  return FALSE;',
      ),
    );
  });
}
