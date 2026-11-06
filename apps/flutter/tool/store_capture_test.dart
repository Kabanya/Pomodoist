// Run explicitly: flutter test tool/store_capture_test.dart.
// Captures production routes with a disposable guest database only.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/billing_store_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/pomo_dependencies.dart';
import 'package:pomodoist/config/startup_wiring.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/audio/focus_sound_player.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/routing/router.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/tasks/widgets/quick_add_dialog.dart';
import 'package:pomodoist/utils/clock.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test/support/test_app.dart';

class _SilentSounds implements FocusSoundPlayer {
  @override
  Future<void> play(FocusSoundCue cue) async {}
  @override
  Future<void> dispose() async {}
}

class _SilentNotifications extends NotificationScheduler {
  @override
  bool get supportsHabitReminders => false;
  @override
  Future<void> scheduleFocusIntervalEnd({
    required DateTime expectedEndAt,
    required String title,
    required String body,
  }) async {}
  @override
  Future<void> cancelFocusNotification() async {}
}

final _config =
    jsonDecode(
          File('../../tool/apple/store-screenshots.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
final _slides = (_config['slides'] as List).cast<List<dynamic>>();
final _now = DateTime.parse(_config['captureDate'] as String);

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadTestAppResources();
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(
          rootBundle.load(Uri.decodeFull(font['asset'] as String)),
        );
      }
      await loader.load();
    }
    for (final (family, path) in [
      ('StoreCJK', '/System/Library/Fonts/Hiragino Sans GB.ttc'),
      ('StoreKorean', '/System/Library/Fonts/AppleSDGothicNeo.ttc'),
      ('StoreArabic', '/System/Library/Fonts/GeezaPro.ttc'),
    ]) {
      final bytes = ByteData.sublistView(await File(path).readAsBytes());
      // Text styles from the bundled theme qualify fallback names by package.
      for (final name in [family, 'packages/shadcn_ui/$family']) {
        await (FontLoader(name)..addFont(Future.value(bytes))).load();
      }
    }
  });
  const selected = String.fromEnvironment(
    'STORE_CAPTURE_LOCALES',
    defaultValue: 'en-US',
  );
  const devices = String.fromEnvironment(
    'STORE_CAPTURE_DEVICES',
    defaultValue: 'iphone',
  );
  final root = Directory(
    const String.fromEnvironment(
      'STORE_CAPTURE_OUTPUT',
      defaultValue: '../../design/app-store/localized/raw',
    ),
  );
  EditableText.debugDeterministicCursor = true;
  for (final localeTag in selected.split(',')) {
    for (final device in devices.split(',')) {
      testWidgets('$device $localeTag production screen captures', (
        tester,
      ) async {
        final locale = switch (localeTag) {
          'pt-BR' => const Locale('pt', 'BR'),
          'zh-Hans' => const Locale('zh'),
          _ => Locale(localeTag.split('-').first),
        };
        final settings =
            (_config['devices'] as Map)[device] as Map<String, dynamic>;
        final pixels = (settings['output'] as List).cast<int>();
        final scale = settings['scale'] as int;
        final size = Size(pixels[0] / scale, pixels[1] / scale);
        debugDefaultTargetPlatformOverride = device == 'mac'
            ? TargetPlatform.macOS
            : TargetPlatform.iOS;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final safeArea = settings['safeArea'] as List;
        tester.view.padding = FakeViewPadding(
          top: (safeArea[0] as num).toDouble(),
          bottom: (safeArea[1] as num).toDouble(),
        );
        SharedPreferences.setMockInitialValues({
          'onboarding.completed.v1': true,
          'launchOffer.shown.v1': true,
          'app.language': localeTag == 'pt-BR' ? 'ptBR' : locale.languageCode,
          'focus.viewMode': 'full',
          timelineVisibleStartMinutesPreferenceKey: 9 * 60,
          timelineVisibleEndMinutesPreferenceKey: 20 * 60,
        });
        final temporary = Directory.systemTemp.createTempSync(
          'pomodoist-store-',
        );
        final databaseFile = File('${temporary.path}/capture.sqlite');
        var db = AppDatabase(NativeDatabase(databaseFile));
        await tester.runAsync(() async {
          await db.ensureSeedData();
          await db.close();
          final seed = await Process.run('python3', [
            '../../tool/apple/seed_store_demo.py',
            databaseFile.path,
            '--date',
            (_config['captureDate'] as String).split('T').first,
          ]);
          expect(seed.exitCode, 0, reason: '${seed.stdout}\n${seed.stderr}');
          debugPrint('FIXTURE ${seed.stdout}');
          db = AppDatabase(NativeDatabase(databaseFile));
        });
        final container = ProviderContainer(
          overrides: [
            ...pomoOverrides,
            appDatabaseProvider.overrideWithValue(db),
            applePurchasesSupportedProvider.overrideWithValue(false),
            focusSoundPlayerProvider.overrideWithValue(_SilentSounds()),
            notificationSchedulerProvider.overrideWithValue(
              _SilentNotifications(),
            ),
            appStartupProvider.overrideWith((ref) async {}),
            accountSyncStartupProvider.overrideWith((ref) async {}),
            startupBackgroundWiringProvider.overrideWith((ref) {}),
            accountProfileProvider.overrideWith((ref) => null),
            clockProvider.overrideWithValue(FixedClock(_now)),
            focusTickerProvider.overrideWith((ref) => Stream.value(_now)),
          ],
        );
        final router = container.read(routerProvider);
        await tester.runAsync(() async {
          (await container
                  .read(focusRepositoryProvider)
                  .startRun(
                    StartFocusRunInput(taskId: 'store-demo-task-00'),
                    now: _now,
                  ))
              .getOrThrow();
        });
        final boundaryKey = GlobalKey();
        final theme = AppTheme.dark();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
              key: boundaryKey,
              child: MaterialApp.router(
                debugShowCheckedModeBanner: false,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    accessibleNavigation: true,
                    alwaysUse24HourFormat: true,
                    textScaler: TextScaler.noScaling,
                  ),
                  child: Builder(
                    builder: (inner) => testAppBuilder(inner, child),
                  ),
                ),
                theme: theme.copyWith(
                  textTheme: theme.textTheme.apply(
                    fontFamilyFallback: [
                      'StoreCJK',
                      'StoreKorean',
                      'StoreArabic',
                    ],
                  ),
                ),
                locale: locale,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                ],
                supportedLocales: AppLocalizations.supportedLocales,
                routerConfig: router,
              ),
            ),
          ),
        );
        Future<void> frames() async {
          for (var i = 0; i < 14; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 15)),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
        }

        final folder = Directory('${root.path}/$device/$localeTag')
          ..createSync(recursive: true);
        for (final slide in _slides) {
          final name = slide[0] as String, route = slide[1] as String;
          router.go(route == '/search' ? '/search?q=homepage' : route);
          await frames();
          if (name.startsWith('07-')) {
            final context = tester.element(find.byType(Scaffold).last);
            showQuickAddDialog(
              context,
              initialText: 'Send the client proposal tomorrow at 10am p2 #Work',
            );
            await frames();
          }
          final texts = find
              .byType(Text)
              .evaluate()
              .map((e) => (e.widget as Text).data)
              .whereType<String>()
              .toList();
          expect(texts, isNotEmpty);
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: scale.toDouble());
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '${folder.path}/$name.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
            await File('${folder.path}/$name.json').writeAsString(
              jsonEncode({
                'locale': localeTag,
                'device': device,
                'route': route,
                'texts': texts,
                'fixture': 'fixed English demo workspace',
                'captureDate': _config['captureDate'],
                'timeZone': _config['timeZone'],
                'source': 'production router and widgets',
              }),
            );
          });
          if (name.startsWith('07-')) {
            final barrier = find.byWidgetPredicate(
              (widget) =>
                  widget is ModalBarrier && widget.color == Colors.black54,
            );
            tester.widget<ModalBarrier>(barrier).onDismiss!();
            await frames();
            expect(barrier, findsNothing);
          }
          debugPrint('CAPTURE $device/$localeTag/$name');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.pumpAndSettle();
        await tester.runAsync(db.close);
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        await tester.runAsync(() => temporary.delete(recursive: true));
      }, timeout: const Timeout(Duration(minutes: 8)));
    }
  }
}
