import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadButton, ShadSwitch;

import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/billing_store_dependencies.dart';
import 'package:pomodoist/config/distraction_dependencies.dart';
import 'package:pomodoist/config/distraction_protection_coordinator.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/pomo_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/data/services/platform/distraction_native_gateway.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';
import 'package:pomodoist/domain/models/notifications/notification_copy.dart';
import 'package:pomodoist/ui/core/widgets/pomodoist_app.dart';

class _OfflineAccount extends AccountBootstrapController {
  @override
  build() async => null;
}

// Notifications are outside this test; never cancel the user's development alerts.
class _Notifications extends NotificationScheduler {
  @override
  bool get supportsHabitReminders => false;
  @override
  Future<void> refreshLanguage() async {}
  @override
  Future<void> initialize() async {}
  @override
  Future<void> cancelFocusNotification() async {}
  @override
  Future<void> cancelHabitNotifications() async {}
  @override
  Future<void> cancelReengagementReminder() async {}
  @override
  Future<void> scheduleReengagementReminder({
    required DateTime firstAt,
    required NotificationCopy copy,
  }) async {}
  @override
  Future<Set<String>> pendingTaskStartTaskIds() async => {};
  @override
  Future<void> scheduleFocusIntervalEnd({
    required DateTime expectedEndAt,
    required String title,
    required String body,
  }) async {}
}

Future<void> _host(
  String step, [
  Map<String, Object?> values = const {},
]) async {
  const address = String.fromEnvironment('BLOCKING_E2E_URL');
  const token = String.fromEnvironment('BLOCKING_E2E_TOKEN');
  if (address.isEmpty || token.isEmpty) {
    throw StateError(
      'Run from the repo root: node tool/macos/blocking-e2e.mjs',
    );
  }
  final uri = Uri.parse(address);
  if (uri.host != '127.0.0.1' || uri.scheme != 'http') {
    throw StateError('E2E control must use IPv4 loopback');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'step': step, ...values}));
    final response = await request.close().timeout(const Duration(seconds: 60));
    final body = await response.transform(utf8.decoder).join();
    expect(response.statusCode, 200, reason: '$step: $body');
  } finally {
    client.close(force: true);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Native window registration must progress before test pumps begin.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('UI configures, blocks and releases macOS apps and Chrome sites', (
    tester,
  ) async {
    if (!Platform.isMacOS) throw UnsupportedError('This UI E2E needs macOS');
    // Check the invocation before mounting any providers or opening local data.
    const controlUrl = String.fromEnvironment('BLOCKING_E2E_URL');
    if (controlUrl.isEmpty) {
      throw StateError(
        'Use node tool/macos/blocking-e2e.mjs from the repo root',
      );
    }
    await _host('register', {'pid': pid});
    debugPrint('E2E UI: isolated Runner registered');
    const testFlavor = String.fromEnvironment(
      'BLOCKING_E2E_FLAVOR',
      defaultValue: 'development',
    );
    setAppFlavor(AppFlavor.values.byName(testFlavor));
    SharedPreferences.setMockInitialValues({
      'onboarding.completed.v1': true,
      'launchOffer.shown.v1': true,
      'app.language': 'en',
      'focus.viewMode': 'full',
    });
    final db = AppDatabase(NativeDatabase.memory());
    final shutdown = <Future<void> Function()>[];
    Future<void> coordinatorShutdown = Future.value();
    final container = ProviderContainer(
      overrides: [
        ...pomoOverrides,
        appDatabaseProvider.overrideWithValue(db),
        accountBootstrapProvider.overrideWith(_OfflineAccount.new),
        applePurchasesSupportedProvider.overrideWithValue(false),
        notificationSchedulerProvider.overrideWithValue(_Notifications()),
        focusRepositoryProvider.overrideWith(
          (ref) => ref.watch(liveFocusRepositoryProvider),
        ),
        protectionCoordinatorProvider.overrideWith((ref) async {
          final focus = ref.watch(liveFocusRepositoryProvider);
          final prefs = await ref.watch(sharedPreferencesProvider.future);
          await coordinatorShutdown;
          if (!ref.mounted) return null;
          final coordinator = ProtectionCoordinator(
            focus: focus,
            native: DistractionNativeGateway(),
            flavor: testFlavor,
            preferences: prefs,
            bridgePort: 0,
            taskTitle: (_) async => null,
          );
          Future<void>? stopping;
          Future<void> stop() => stopping ??= coordinator.dispose();
          shutdown.add(stop);
          ref.onDispose(() => coordinatorShutdown = stop());
          await coordinator.start();
          return coordinator;
        }),
      ],
    );
    addTearDown(() async {
      for (final stop in shutdown) {
        await stop();
      }
      container.dispose();
      await db.close();
    });
    await container.read(sharedPreferencesProvider.future);
    debugPrint('E2E UI: temporary preferences ready');
    container.read(accountBootstrapProvider);
    debugPrint('E2E UI: offline account ready');
    // The macOS host uses explicit views; pumping an implicit view renders into
    // the hidden bootstrap window instead of the actual application window.
    binding.deviceEventDispatcher = null;
    await tester.runAsync(
      () => runMultiApp(
        home: (_, _) => const PomodoistApp(),
        globalScope: (child) =>
            UncontrolledProviderScope(container: container, child: child),
        config: MultiAppConfig(
          globalWindowOptions: const WindowOptions(
            size: Size(1280, 900),
            titleBarStyle: TitleBarStyle.normal,
            windowButtonVisibility: true,
          ),
          macosParams: const MacosPlatformParams(
            closeAppAfterLastWindowClosed: false,
            saveLastWindowToReopen: false,
          ),
        ),
      ).timeout(const Duration(seconds: 20)),
    );
    debugPrint('E2E UI: mounting PomodoistApp');

    Future<void> until(bool Function() condition, String reason) async {
      final watch = Stopwatch()..start();
      bool ready() {
        try {
          return condition();
        } on StateError {
          // A .first/.last finder has no candidate while a route is mounting.
          return false;
        }
      }

      while (!ready()) {
        if (watch.elapsed > const Duration(seconds: 20)) {
          debugPrintSynchronously(
            'Visible UI: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().join(' | ')}',
          );
          fail('Timed out: $reason');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull, reason: reason);
    }

    Future<void> tap(Finder finder) async {
      await until(
        () => finder.evaluate().isNotEmpty,
        finder.describeMatch(Plurality.one),
      );
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 250));
    }

    Finder button(String label) => find.widgetWithText(ShadButton, label);
    Finder dialogButton(String label) =>
        find.descendant(of: find.byType(AlertDialog), matching: button(label));
    Finder dialogInput() => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(EditableText),
    );

    Future<void> choose(Finder dropdown, String label) async {
      await tap(dropdown);
      await tap(find.text(label).last);
    }

    await tap(find.text('Blocking').first);
    final discovery = find.descendant(
      of: find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Discover used apps',
      ),
      matching: find.byType(ShadSwitch),
    );
    await tap(discovery);
    await until(
      () => tester.widget<ShadSwitch>(discovery).value,
      'discovery enabled',
    );
    await _host('discover', {'pid': pid});
    await tester.pump(const Duration(milliseconds: 300));

    await tap(button('Add profile'));
    await tester.enterText(dialogInput(), 'E2E blocking');
    await tap(find.widgetWithText(FilterChip, 'Social media').last);
    await tap(dialogButton('Save'));
    await until(
      () => find.byType(AlertDialog).evaluate().isEmpty,
      'profile saved',
    );
    await choose(
      find.byType(DropdownButtonFormField<String>).first,
      'E2E blocking',
    );
    await tap(button('Resources and exceptions'));

    Future<void> addSite(String host) async {
      await tap(button('Add site'));
      await tester.enterText(dialogInput(), host);
      await tap(dialogButton('Save'));
      await until(
        () => find.byType(AlertDialog).evaluate().isEmpty,
        'site saved',
      );
    }

    await addSite('blocked.blocking.test');
    await addSite('allowed.blocked.blocking.test');

    Finder resource(String name) => find
        .ancestor(of: find.text(name).first, matching: find.byType(Column))
        .first;
    Finder resourceDropdown(String name, int index) => find
        .descendant(
          of: resource(name),
          matching: find.byType(DropdownButtonFormField<String>),
        )
        .at(index);
    await until(
      () => find
          .text('macos:com.pomodoist.blocking-e2e.fixture')
          .evaluate()
          .isNotEmpty,
      'native foreground discovery',
    );
    await choose(
      resourceDropdown('macos:com.pomodoist.blocking-e2e.fixture', 0),
      'Social media',
    );
    await choose(resourceDropdown('blocked.blocking.test', 0), 'Social media');
    await choose(
      resourceDropdown('allowed.blocked.blocking.test', 0),
      'Social media',
    );
    await choose(
      resourceDropdown('allowed.blocked.blocking.test', 1),
      'Always allow',
    );
    await tap(button('Close'));

    await tap(button('Show pairing code'));
    final codeFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          RegExp(r'^Code \d+-\d{6} · port \d+$').hasMatch(widget.data ?? ''),
    );
    await until(
      () => codeFinder.evaluate().isNotEmpty,
      'pairing code displayed',
    );
    final match = RegExp(
      r'^Code (\d+-\d{6}) · port (\d+)$',
    ).firstMatch(tester.widget<Text>(codeFinder).data!)!;
    await _host('before', {
      'code': match.group(1),
      'port': int.parse(match.group(2)!),
    });

    await tap(button('Start focus'));
    await until(
      () => find.byKey(const Key('focus-details-menu')).evaluate().isNotEmpty,
      'Focus started through UI',
    );
    await _host('blocked');
    await tap(find.byKey(const Key('focus-details-menu')));
    await tap(find.text('Stop').last);
    await until(
      () => find.byKey(const Key('focus-details-menu')).evaluate().isEmpty,
      'Focus stopped through UI',
    );
    await _host('after');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
