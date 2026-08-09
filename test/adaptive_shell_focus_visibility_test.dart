import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/app/widgets/adaptive_shell.dart';
import 'package:pomodoist/features/focus/domain/focus_models.dart';
import 'package:pomodoist/features/productivity/domain/achievement_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final layout in const {
    'compact': Size(600, 800),
    'wide': Size(1200, 900),
  }.entries) {
    testWidgets(
      'active mini player hides on Focus paths and returns on ${layout.key}',
      (tester) async {
        await _pumpShell(tester, size: layout.value);

        expect(_miniPlayerSurface, findsOneWidget);

        await tester.tap(find.byKey(const Key('go-focus')));
        await _pumpShellFrame(tester);

        expect(_miniPlayerSurface, findsNothing);

        await tester.tap(find.byKey(const Key('go-nested-focus')));
        await _pumpShellFrame(tester);

        expect(_miniPlayerSurface, findsNothing);

        await tester.tap(find.byKey(const Key('go-today')));
        await _pumpShellFrame(tester);

        expect(_miniPlayerSurface, findsOneWidget);
      },
    );
  }

  testWidgets(
    'compact Focus keeps bottom navigation and one pause action surface',
    (tester) async {
      await _pumpShell(
        tester,
        size: const Size(600, 800),
        initialLocation: '/focus',
      );

      expect(find.byKey(const Key('mobile-bottom-navigation')), findsOneWidget);
      expect(_miniPlayerSurface, findsNothing);
      expect(find.byTooltip('Pause'), findsOneWidget);
    },
  );
}

Finder get _miniPlayerSurface =>
    find.byKey(const Key('mini-focus-player-surface'));

Future<void> _pumpShell(
  WidgetTester tester, {
  required Size size,
  String initialLocation = '/today',
}) async {
  final previousSize = tester.view.physicalSize;
  final previousDevicePixelRatio = tester.view.devicePixelRatio;
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..physicalSize = previousSize
      ..devicePixelRatio = previousDevicePixelRatio;
  });

  final now = DateTime.utc(2026, 7, 10, 10);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        focusRepositoryProvider.overrideWithValue(_ActiveFocusRepository(now)),
        focusTickerProvider.overrideWith((ref) => Stream.value(now)),
        currentUserProvider.overrideWith((ref) => Stream.value(null)),
        tasksByQueryProvider.overrideWith(
          (ref, query) => Stream.value(const []),
        ),
        projectsProvider.overrideWith((ref) => Stream.value(const [])),
        achievementRepositoryProvider.overrideWithValue(
          const _NoopAchievementRepository(),
        ),
        achievementsProvider.overrideWith(
          (ref) => Stream.value(const <AchievementItem>[]),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: _AdaptiveShellRouteHarness(initialLocation: initialLocation),
      ),
    ),
  );
  await _pumpShellFrame(tester);
}

Future<void> _pumpShellFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

class _AdaptiveShellRouteHarness extends StatefulWidget {
  const _AdaptiveShellRouteHarness({required this.initialLocation});

  final String initialLocation;

  @override
  State<_AdaptiveShellRouteHarness> createState() =>
      _AdaptiveShellRouteHarnessState();
}

class _AdaptiveShellRouteHarnessState
    extends State<_AdaptiveShellRouteHarness> {
  late String _location = widget.initialLocation;

  @override
  Widget build(BuildContext context) {
    final onFocus = _location == '/focus';
    return AdaptiveShell(
      location: _location,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onFocus)
              IconButton(
                tooltip: 'Pause',
                onPressed: () {},
                icon: const Icon(Icons.pause),
              ),
            TextButton(
              key: const Key('go-focus'),
              onPressed: () => setState(() => _location = '/focus'),
              child: const Text('Open Focus'),
            ),
            TextButton(
              key: const Key('go-nested-focus'),
              onPressed: () => setState(() => _location = '/focus/session'),
              child: const Text('Open nested Focus'),
            ),
            TextButton(
              key: const Key('go-today'),
              onPressed: () => setState(() => _location = '/today'),
              child: const Text('Open Today'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveFocusRepository implements FocusRepository {
  _ActiveFocusRepository(this.now);

  final DateTime now;

  @override
  Stream<FocusRunItem?> watchActiveRun() => Stream.value(
    FocusRunItem(
      id: 'run',
      userId: 'user',
      presetId: 'preset',
      status: 'active',
      startedAt: now,
      targetWorkIntervals: 2,
      completedWorkIntervals: 0,
      createdAt: now,
      updatedAt: now,
    ),
  );

  @override
  Stream<FocusIntervalItem?> watchActiveInterval() => Stream.value(
    FocusIntervalItem(
      id: 'interval',
      runId: 'run',
      type: 'work',
      status: 'running',
      plannedSeconds: 25 * 60,
      startedAt: now,
      pausedTotalSeconds: 0,
      sequenceNumber: 1,
      createdAt: now,
      updatedAt: now,
    ),
  );

  @override
  Stream<List<FocusPresetItem>> watchPresets() => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopAchievementRepository implements AchievementRepository {
  const _NoopAchievementRepository();

  @override
  Stream<List<AchievementItem>> watchAchievements() => Stream.value(const []);

  @override
  Future<List<AchievementItem>> takePendingAnnouncements(
    List<AchievementItem> items,
  ) async => const [];
}
