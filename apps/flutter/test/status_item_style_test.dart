import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/settings/status_item_style_repository_native.dart';
import 'package:pomodoist/domain/models/settings/status_item_style.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/settings/view_models/status_item_style_view_model.dart';
import 'package:pomodoist/ui/settings/widgets/status_item_style_settings.dart';

import 'support/test_app.dart';

const channel = MethodChannel('pomodoist/status_item');

Future<void> nativeChange(String style) async {
  final done = Completer<void>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('styleChanged', style),
        ),
        (_) => done.complete(),
      );
  await done.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!kIsWeb) await loadTestAppResources();
  });
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String stored = 'classic';
  bool fail = false;
  Completer<String>? pending;
  setUp(() {
    stored = 'classic';
    fail = false;
    pending = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (fail) throw PlatformException(code: 'unavailable');
      if (call.method == 'getStyle') {
        return pending?.future ?? Future.value(stored);
      }
      if (call.method == 'setStyle') {
        if (pending != null) return pending!.future;
        stored = call.arguments as String;
        return stored;
      }
      throw MissingPluginException();
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('native repository reads and applies the acknowledged style', () async {
    final repository = NativeStatusItemStyleRepository();
    addTearDown(repository.dispose);
    expect(await repository.read(), StatusItemStyle.classic);
    expect(
      await repository.select(StatusItemStyle.modern),
      StatusItemStyle.modern,
    );
    expect(stored, 'modern');
    expect(await repository.read(), StatusItemStyle.modern);
  });

  test(
    'native notifications deliver menu changes and reject malformed values',
    () async {
      final repository = NativeStatusItemStyleRepository();
      addTearDown(repository.dispose);
      final changes = <StatusItemStyle>[];
      final subscription = repository.changes.listen(changes.add);
      addTearDown(subscription.cancel);
      await nativeChange('modern');
      await nativeChange('unsupported');
      await nativeChange('classic');
      expect(changes, [StatusItemStyle.modern, StatusItemStyle.classic]);
      stored = 'unsupported';
      await expectLater(repository.read(), throwsStateError);
    },
  );

  test(
    'settings retain acknowledged selection on failure and can retry',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final subscription = container.listen(statusItemStyleProvider, (_, _) {});
      addTearDown(subscription.close);
      final controller = container.read(statusItemStyleProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(statusItemStyleProvider).style,
        StatusItemStyle.classic,
      );
      pending = Completer<String>();
      final selecting = controller.select(StatusItemStyle.modern);
      expect(
        container.read(statusItemStyleProvider).style,
        StatusItemStyle.classic,
      );
      pending!.completeError(PlatformException(code: 'unavailable'));
      await selecting;
      expect(
        container.read(statusItemStyleProvider).style,
        StatusItemStyle.classic,
      );
      expect(container.read(statusItemStyleProvider).error, isNotNull);
      pending = null;
      await controller.select(StatusItemStyle.modern);
      expect(
        container.read(statusItemStyleProvider).style,
        StatusItemStyle.modern,
      );
      expect(container.read(statusItemStyleProvider).error, isNull);
      await nativeChange('classic');
      expect(
        container.read(statusItemStyleProvider).style,
        StatusItemStyle.classic,
      );
    },
  );

  test('a menu event wins over an older read response', () async {
    pending = Completer<String>();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(statusItemStyleProvider, (_, _) {});
    addTearDown(subscription.close);
    await Future<void>.delayed(Duration.zero);
    await nativeChange('modern');
    pending!.complete('classic');
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(statusItemStyleProvider).style,
      StatusItemStyle.modern,
    );
    expect(container.read(statusItemStyleProvider).isBusy, isFalse);
  });

  testWidgets('Mac selector follows native menu and retries a failed load', (
    tester,
  ) async {
    fail = true;
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    if (kIsWeb) {
      expect(find.text('Menu bar timer'), findsNothing);
      return;
    }
    expect(find.text('Menu bar timer'), findsOneWidget);
    expect(
      find.text('Could not update the menu bar timer. Please try again.'),
      findsOneWidget,
    );
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Old'), findsOneWidget);
    await tester.tap(find.text('Old'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New').last);
    await tester.pumpAndSettle();
    expect(stored, 'modern');
    await nativeChange('classic');
    await tester.pumpAndSettle();
    expect(find.text('Old'), findsOneWidget);
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));

  for (final platform in TargetPlatform.values.where(
    (p) => p != TargetPlatform.macOS,
  )) {
    testWidgets('selector is absent on $platform', (tester) async {
      await tester.pumpWidget(_app());
      expect(find.text('Menu bar timer'), findsNothing);
      expect(find.byType(StatusItemStyleSettings), findsOneWidget);
    }, variant: TargetPlatformVariant({platform}));
  }

  testWidgets('failed selection restores the visible acknowledged style', (
    tester,
  ) async {
    if (kIsWeb) return;
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    fail = true;
    await tester.tap(find.text('Old'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New').last);
    await tester.pumpAndSettle();
    expect(find.text('Old'), findsOneWidget);
    expect(find.text('New'), findsNothing);
    expect(stored, 'classic');
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('New'), findsOneWidget);
    expect(stored, 'modern');
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));
}

Widget _app() => kIsWeb
    ? const StatusItemStyleSettings()
    : ProviderScope(
        child: MaterialApp(
          builder: testAppBuilder,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: StatusItemStyleSettings()),
        ),
      );
