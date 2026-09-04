import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner disables Impeller before constructing FlutterWindow', () {
    final runner = File('windows/runner/main.cpp').readAsStringSync();

    final impellerOffset =
        runner.indexOf('project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);');
    final windowOffset = runner.indexOf('FlutterWindow window(project);');

    expect(impellerOffset, greaterThanOrEqualTo(0));
    expect(windowOffset, greaterThan(impellerOffset));
  });

  test('Windows multiview compatibility bridge forwards the Impeller switch', () {
    final bridge = File(
      'windows/runner/multiview_desktop_impeller_bridge.h',
    ).readAsStringSync();
    final implementation = File(
      'windows/runner/multiview_desktop_impeller_bridge.cpp',
    ).readAsStringSync();
    final cmake = File('windows/CMakeLists.txt').readAsStringSync();

    expect(bridge, contains('#define FlutterDesktopEngineCreate'));
    expect(implementation, contains('auto configured = *properties;'));
    expect(
      implementation,
      contains('configured.impeller_switch = DisabledImpeller;'),
    );
    expect(implementation, contains('FlutterDesktopEngineCreate(&configured)'));
    expect(cmake, contains('multiview_desktop_impeller_bridge.cpp'));
    expect(cmake, contains('/FI'));
    expect(cmake, contains('multiview_desktop_impeller_bridge.h'));
  });

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
