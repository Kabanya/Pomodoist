import 'support/test_app.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pomodoist/config/update_dependencies.dart';
import 'package:pomodoist/domain/models/updates/update_contracts.dart';
import 'package:pomodoist/domain/models/updates/update_release.dart';
import 'package:pomodoist/ui/updates/view_models/update_view_model.dart';
import 'package:pomodoist/ui/updates/widgets/update_widgets.dart';

import 'desktop_update_controller_test.dart' as support;

void main() {
  setUpAll(loadTestAppResources);
  testWidgets(
    'router popup has an Overlay, closes without installing, stays dismissed',
    (tester) async {
      final installer = support.FakeUpdateInstaller();
      final controller = support.testController(installer: installer);
      final container = ProviderContainer(
        overrides: [updateRepositoryProvider.overrideWithValue(controller)],
      );
      addTearDown(container.dispose);
      addTearDown(controller.dispose);
      container.listen(updateViewModelProvider, (_, _) {});
      final view = container.read(updateViewModelProvider.notifier);
      await view.check();
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const Scaffold())],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
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
      await view.check();
      await tester.pumpAndSettle();
      expect(find.byType(DesktopUpdatePopup), findsNothing);
      await view.check(manual: true);
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
    final controller = support.testController(officialUpdatesAllowed: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [updateRepositoryProvider.overrideWithValue(controller)],
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
        overrides: [updateRepositoryProvider.overrideWithValue(controller)],
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
      addTearDown(controller.dispose);
      await controller.check();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [updateRepositoryProvider.overrideWithValue(controller)],
          child: const MaterialApp(
            builder: testAppBuilder,
            home: Scaffold(body: DesktopUpdatePopup()),
          ),
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
      expect(controller.state.phase, UpdatePhase.installing);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('Settings can enable RC and manually check updates', (
    tester,
  ) async {
    final source = support.FakeUpdateSource();
    final controller = support.testController(source: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [updateRepositoryProvider.overrideWithValue(controller)],
        child: const MaterialApp(
          builder: testAppBuilder,
          home: Scaffold(body: DesktopUpdateSettings()),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('desktop-update-rc')));
    await tester.pumpAndSettle();
    expect(controller.state.channel, UpdateChannel.rc);
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
      final installer = support.FakeUpdateInstaller()..gate = Completer<void>();
      final controller = support.testController(installer: installer);
      await controller.check();
      final updating = controller.update();
      installer.report!(UpdatePhase.verifying, null);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [updateRepositoryProvider.overrideWithValue(controller)],
          child: const MaterialApp(
            builder: testAppBuilder,
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(360, 640),
                disableAnimations: true,
              ),
              child: Scaffold(body: DesktopUpdatePopup()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      installer.gate!.complete();
      await updating;
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
