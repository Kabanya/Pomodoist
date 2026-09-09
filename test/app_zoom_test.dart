import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/app_zoom.dart';
import 'package:pomodoist/app/keyboard_shortcuts.dart';
import 'package:pomodoist/features/focus/presentation/focus_view_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('zoom steps, clamps, resets and persists between containers', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(appZoomProvider.notifier);
    expect(container.read(appZoomProvider), 100);
    await controller.apply(AppZoomCommand.increase);
    expect(container.read(appZoomProvider), 110);
    await controller.apply(AppZoomCommand.decrease);
    expect(container.read(appZoomProvider), 100);
    for (var i = 0; i < 20; i++) {
      await controller.apply(AppZoomCommand.increase);
    }
    expect(container.read(appZoomProvider), 150);
    for (var i = 0; i < 20; i++) {
      await controller.apply(AppZoomCommand.decrease);
    }
    expect(container.read(appZoomProvider), 70);
    await controller.apply(AppZoomCommand.reset);
    expect(container.read(appZoomProvider), 100);
    await controller.apply(AppZoomCommand.increase);
    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    restored.read(appZoomProvider);
    await restored.read(sharedPreferencesProvider.future);
    expect(restored.read(appZoomProvider), 110);
  });

  test('reset before preferences load wins over saved zoom', () async {
    SharedPreferences.setMockInitialValues({appZoomPreferenceKey: 140});
    final pending = Completer<SharedPreferences?>();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => pending.future),
      ],
    );
    addTearDown(container.dispose);
    final reset = container
        .read(appZoomProvider.notifier)
        .apply(AppZoomCommand.reset);
    expect(container.read(appZoomProvider), 100);
    pending.complete(await SharedPreferences.getInstance());
    await reset;
    expect(container.read(appZoomProvider), 100);
    expect(
      (await SharedPreferences.getInstance()).getInt(appZoomPreferenceKey),
      100,
    );
  });

  test('invalid preferences are safe and zoom works without storage', () async {
    for (final (saved, expected) in [(999, 150), (-50, 70), ('bad', 100)]) {
      SharedPreferences.setMockInitialValues({appZoomPreferenceKey: saved});
      final container = ProviderContainer();
      container.read(appZoomProvider);
      await container.read(sharedPreferencesProvider.future);
      expect(container.read(appZoomProvider), expected);
      container.dispose();
    }
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWith((ref) async => null)],
    );
    addTearDown(container.dispose);
    await container
        .read(appZoomProvider.notifier)
        .apply(AppZoomCommand.increase);
    expect(container.read(appZoomProvider), 110);
  });

  test(
    'viewport and insets scale together without overriding accessibility',
    () {
      const media = MediaQueryData(
        size: Size(1200, 900),
        devicePixelRatio: 2,
        padding: EdgeInsets.only(top: 24),
        viewPadding: EdgeInsets.only(top: 24),
        viewInsets: EdgeInsets.only(bottom: 240),
        systemGestureInsets: EdgeInsets.all(12),
        textScaler: TextScaler.linear(1.2),
        disableAnimations: true,
      );
      final zoomed = zoomedMediaQuery(media, const Size(900, 600), 1.5);
      expect(zoomed.size, const Size(600, 400));
      expect(zoomed.devicePixelRatio, 3);
      expect(zoomed.padding.top, 16);
      expect(zoomed.viewPadding.top, 16);
      expect(zoomed.viewInsets.bottom, 160);
      expect(zoomed.systemGestureInsets.left, 8);
      expect(zoomed.textScaler, media.textScaler);
      expect(zoomed.disableAnimations, isTrue);
      expect(zoomedMediaQuery(media, media.size, 1), media);
    },
  );
}
