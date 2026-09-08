import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/updates/update_contracts.dart';
import 'package:pomodoist/features/updates/update_providers.dart';
import 'package:pomodoist/features/updates/update_widgets.dart';
import 'package:pomodoist/features/updates/update_release.dart';

import 'desktop_update_controller_test.dart' as support;

void main() {
  testWidgets('bottom-right popup shows version, closes without installing, stays dismissed', (tester) async {
    final installer = support.FakeUpdateInstaller();
    final controller = support.testController(installer: installer);
    await controller.check();
    await tester.pumpWidget(ProviderScope(overrides: [
      desktopUpdateControllerProvider.overrideWithValue(controller),
    ], child: const MaterialApp(home: DesktopUpdateHost(child: Scaffold()))));
    await tester.pumpAndSettle();
    expect(find.text('×'), findsOneWidget);
    expect(find.byKey(const Key('desktop-update-version')), findsOneWidget);
    expect(find.byKey(const Key('desktop-update-install')), findsOneWidget);
    final popup = tester.getRect(find.byType(DesktopUpdatePopup));
    expect(popup.right, closeTo(784, 1));
    expect(popup.bottom, closeTo(584, 1));
    await tester.tap(find.byKey(const Key('desktop-update-close')));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopUpdatePopup), findsNothing);
    expect(installer.installs, 0);
    await controller.check();
    await tester.pumpAndSettle();
    expect(find.byType(DesktopUpdatePopup), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('Update starts exactly once and animates download, verification and installation', (tester) async {
    final installer = support.FakeUpdateInstaller()..gate = Completer<void>();
    final controller = support.testController(installer: installer);
    await controller.check();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DesktopUpdatePopup(controller: controller))));
    await tester.tap(find.byKey(const Key('desktop-update-install')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(installer.installs, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('25%'), findsOneWidget);
    await tester.tap(find.byKey(const Key('desktop-update-install')));
    expect(installer.installs, 1);
    installer.report!(UpdatePhase.verifying, null);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Verifying integrity…'), findsOneWidget);
    installer.gate!.complete();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.phase, UpdatePhase.installing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('Settings can enable RC and manually check updates', (tester) async {
    final source = support.FakeUpdateSource();
    final controller = support.testController(source: source);
    await tester.pumpWidget(ProviderScope(overrides: [
      desktopUpdateControllerProvider.overrideWithValue(controller),
    ], child: const MaterialApp(home: Scaffold(body: DesktopUpdateSettings()))));
    await tester.tap(find.byKey(const Key('desktop-update-rc')));
    await tester.pumpAndSettle();
    expect(controller.channel, UpdateChannel.rc);
    expect(source.lastChannel, UpdateChannel.rc);
    final before = source.calls;
    await tester.tap(find.byKey(const Key('desktop-update-check')));
    await tester.pumpAndSettle();
    expect(source.calls, before + 1);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('compact window and reduced motion do not overflow or keep animating', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = support.testController();
    await controller.check();
    controller.phase = UpdatePhase.verifying;
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(size: Size(360, 640), disableAnimations: true),
      child: Scaffold(body: DesktopUpdatePopup(controller: controller)))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
