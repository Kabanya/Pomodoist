import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows multiview helper registers every generated plugin once', () {
    final generated = File(
      'windows/flutter/generated_plugin_registrant.cc',
    ).readAsStringSync();
    final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final pluginPattern = RegExp(r'([A-Za-z0-9]+RegisterWithRegistrar)\(');
    final expected = pluginPattern
        .allMatches(generated)
        .map((match) => match.group(1)!)
        .where(
          (plugin) => plugin != 'MultiViewDesktopPluginRegisterWithRegistrar',
        )
        .toSet();
    final actual = pluginPattern
        .allMatches(runner)
        .map((match) => match.group(1)!)
        .toSet();

    expect(actual, expected);
  });

  test('Windows host forwards warm app links to Dart', () {
    final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(runner, contains('message == WM_COPYDATA'));
    expect(runner, contains('native_link_channel_->InvokeMethod('));
    expect(
      runner,
      isNot(contains('FlutterDesktopEngineProcessExternalWindowMessage(')),
      reason: 'That API handles lifecycle messages, not plugin delegates.',
    );
  });

  test('Linux runner exposes the X11 global hotkey fallback', () {
    final runner = File('linux/runner/my_application.cc').readAsStringSync();

    expect(runner, contains('XGrabKey'));
    expect(runner, contains('portal_unavailable'));
    expect(runner, contains('showQuickAdd'));
  });
}
