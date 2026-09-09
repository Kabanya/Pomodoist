import 'support/test_app.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/features/updates/update_contracts.dart';
import 'package:pomodoist/features/updates/update_providers.dart';
import 'package:pomodoist/features/updates/update_widgets.dart';
import 'package:pomodoist/features/updates/update_release.dart';

import 'desktop_update_controller_test.dart' as support;

void main() {
  setUpAll(loadTestAppResources);
  testWidgets(
    'router popup has an Overlay, closes without installing, stays dismissed',
    (tester) async {
      final installer = support.FakeUpdateInstaller();
      final controller = support.testController(installer: installer);
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const Scaffold())],
      );
      addTearDown(router.dispose);
      await controller.check();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            desktopUpdateControllerProvider.overrideWithValue(controller),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => testAppBuilder(
              context,
              DesktopUpdateHost(child: child ?? const SizedBox.shrink()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('desktop-update-close')), findsOneWidget);
      expect(find.byKey(const Key('desktop-update-version')), findsOneWidget);
      expect(find.byKey(const Key('desktop-update-install')), findsOneWidget);
      expect(
        Overlay.maybeOf(tester.element(find.byType(DesktopUpdatePopup))),
        isNotNull,
      );
      expect(
        tester.state<TooltipState>(find.byType(Tooltip)).ensureTooltipVisible(),
        isTrue,
      );
      await tester.pump();
      expect(find.text('Close'), findsOneWidget);
      Tooltip.dismissAllToolTips();
      await tester.pump();
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
      await controller.check(manual: true);
      await tester.pumpAndSettle();
      expect(find.byType(DesktopUpdatePopup), findsOneWidget);
      await tester.tap(find.byKey(const Key('desktop-update-install')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(installer.installs, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('unofficial build suppresses popup and update controls', (
    tester,
  ) async {
    final controller = support.testController(officialUpdatesAllowed: false)
      ..offer = support.testOffer()
      ..popupVisible = true;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopUpdateControllerProvider.overrideWithValue(controller),
        ],
        child: const MaterialApp(
          builder: testAppBuilder,
          home: Scaffold(
            body: Column(
              children: [
                Expanded(child: DesktopUpdateHost(child: SizedBox.expand())),
                DesktopUpdateSettings(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DesktopUpdatePopup), findsNothing);
    expect(
      find.text(
        'This build is updated by its owner to preserve its server configuration. Ask them for the latest version.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('desktop-update-settings')), findsNothing);
    expect(find.byKey(const Key('desktop-update-check')), findsNothing);
  });

  testWidgets('production non-AppImage keeps package manager guidance', (
    tester,
  ) async {
    final installer = support.FakeUpdateInstaller()
      ..unavailableReason = 'Not an AppImage';
    final controller = support.testController(installer: installer);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopUpdateControllerProvider.overrideWithValue(controller),
        ],
        child: const MaterialApp(
          builder: testAppBuilder,
          home: Scaffold(body: DesktopUpdateSettings()),
        ),
      ),
    );

    expect(
      find.text(
        'Automatic updates are available in the official Linux AppImage. Use your package manager for other builds.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('desktop-update-settings')), findsNothing);
  });

  testWidgets(
    'Update starts exactly once and animates download, verification and installation',
    (tester) async {
      final installer = support.FakeUpdateInstaller()..gate = Completer<void>();
      final controller = support.testController(installer: installer);
      await controller.check();
      await tester.pumpWidget(
        MaterialApp(
          builder: testAppBuilder,
          home: Scaffold(body: DesktopUpdatePopup(controller: controller)),
        ),
      );
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
    },
  );

  testWidgets('Settings can enable RC and manually check updates', (
    tester,
  ) async {
    final source = support.FakeUpdateSource();
    final controller = support.testController(source: source);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopUpdateControllerProvider.overrideWithValue(controller),
        ],
        child: const MaterialApp(
          builder: testAppBuilder,
          home: Scaffold(body: DesktopUpdateSettings()),
        ),
      ),
    );
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

  testWidgets(
    'compact window and reduced motion do not overflow or keep animating',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = support.testController();
      await controller.check();
      controller.phase = UpdatePhase.verifying;
      await tester.pumpWidget(
        MaterialApp(
          builder: testAppBuilder,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              disableAnimations: true,
            ),
            child: Scaffold(body: DesktopUpdatePopup(controller: controller)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
