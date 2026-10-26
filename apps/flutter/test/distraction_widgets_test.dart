import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/distractions/distraction_repository.dart';
import 'package:pomodoist/domain/models/distractions/distraction_models.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/distractions/view_models/distraction_view_model.dart';
import 'package:pomodoist/ui/distractions/widgets/distraction_settings.dart';
import 'package:pomodoist/ui/distractions/widgets/focus_exit_host.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadButton, ShadInput;

import 'support/test_app.dart';

final _work = DistractionProfile.fromJson({
  'id': 'work',
  'name': 'Work',
  'blockedCategories': ['video'],
  'overrides': <Map<String, dynamic>>[],
});
final _youtube = ResourceAssignment.fromJson({
  'kind': 'domain',
  'id': 'youtube.com',
  'name': 'YouTube',
  'category': 'video',
  'source': 'manual',
});

class _Commands implements DistractionRepository {
  _Commands(this.state);
  @override
  DistractionSettingsState state;
  final _changes = StreamController<void>.broadcast(sync: true);
  final calls = <String>[];
  final profiles = <DistractionProfile>[];
  final assignments = <ResourceAssignment>[];
  final configurations = <Map<String, Object?>>[];
  Object? saveError;

  void emit(DistractionSettingsState next) {
    state = next;
    _changes.add(null);
  }

  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<void> configure({
    String? profileId,
    int? strictExitSeconds,
    bool? discovery,
    bool? collectAttempts,
    bool? automatic,
    bool clearProfile = false,
  }) async => configurations.add({
    'profileId': profileId,
    'strictExitSeconds': strictExitSeconds,
    'discovery': discovery,
    'collectAttempts': collectAttempts,
    'automatic': automatic,
    'clearProfile': clearProfile,
  });
  @override
  Future<void> saveProfile(DistractionProfile profile) async {
    if (saveError case final error?) throw error;
    profiles.add(profile);
  }

  @override
  Future<void> saveAssignment(ResourceAssignment value) async =>
      assignments.add(value);
  @override
  Future<void> classify(ResourceAssignment resource) async =>
      calls.add('classify:${resource.id}');
  @override
  Future<void> pair() async => calls.add('pair');
  @override
  Future<void> cancelExit() async => calls.add('cancelExit');
  @override
  Future<void> confirmExit() async => calls.add('confirmExit');
  @override
  Future<void> requestExit() async => calls.add('requestExit');
  @override
  Future<void> joinShared() async => calls.add('joinShared');
  @override
  Future<void> finishLocal() async => calls.add('finishLocal');
  @override
  Future<bool> detach() async {
    calls.add('detach');
    return true;
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Commands commands,
  Widget child, {
  double width = 360,
  Brightness brightness = Brightness.light,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(commands._changes.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        distractionCommandsProvider.overrideWithValue(commands),
        distractionViewModelProvider.overrideWith((ref) {
          final subscription = commands.changes.listen(
            (_) => ref.invalidateSelf(),
          );
          ref.onDispose(subscription.cancel);
          return commands.state;
        }),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.dark()
            : AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: Builder(builder: (context) => testAppBuilder(context, child)),
        ),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _settings() => const Scaffold(
  body: SingleChildScrollView(
    child: Padding(padding: EdgeInsets.all(24), child: DistractionSettings()),
  ),
);

Finder _button(String text) => find.widgetWithText(ShadButton, text);

void main() {
  setUpAll(loadTestAppResources);

  for (final width in [360.0, 1200.0]) {
    for (final brightness in Brightness.values) {
      for (final reduceMotion in [false, true]) {
        final configuration =
            '$width ${brightness.name} reduceMotion=$reduceMotion';
        testWidgets('settings profile editing works at $configuration', (
          tester,
        ) async {
          final commands = _Commands(
            DistractionSettingsState(
              available: true,
              profiles: [_work],
              profileId: 'work',
              assignments: [_youtube],
              online: true,
            ),
          );
          await _mount(
            tester,
            commands,
            _settings(),
            width: width,
            brightness: brightness,
            reduceMotion: reduceMotion,
          );
          expect(find.text('Distraction blocking'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(_button('Edit profile'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(tester.takeException(), isNull);
          final name = find.descendant(
            of: find.byType(ShadInput),
            matching: find.byType(EditableText),
          );
          await tester.enterText(name, 'Deep work');
          await tester.tap(find.widgetWithText(FilterChip, 'Social media'));
          await tester.pump();
          expect(
            tester
                .widget<FilterChip>(
                  find.widgetWithText(FilterChip, 'Social media'),
                )
                .selected,
            isTrue,
          );
          await tester.ensureVisible(_button('Save'));
          await tester.tap(_button('Save'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(commands.profiles.single.id, 'work');
          expect(commands.profiles.single.name, 'Deep work');
          expect(
            commands.profiles.single.blockedCategories,
            containsAll(['video', 'social']),
          );
          expect(commands.profiles.single.blockOnPause, isTrue);
          expect(tester.takeException(), isNull);
        });

        testWidgets('countdown and local badge work at $configuration', (
          tester,
        ) async {
          final commands = _Commands(
            const DistractionSettingsState(
              available: true,
              active: true,
              local: true,
              strict: true,
              strictExitSeconds: 60,
              exitPending: true,
              exitRemaining: 37,
            ),
          );
          // No Scaffold/Material ancestor: the local Chip must supply its own Material.
          await _mount(
            tester,
            commands,
            const FocusExitHost(child: ColoredBox(color: Colors.transparent)),
            width: width,
            brightness: brightness,
            reduceMotion: reduceMotion,
          );
          expect(find.text('Local Focus · this computer'), findsOneWidget);
          expect(
            find.text(
              'Exit available in 37 seconds. You can cancel and return to Focus.',
            ),
            findsOneWidget,
          );
          expect(_button('Confirm exit'), findsNothing);
          expect(tester.takeException(), isNull);
          final semantics = tester.ensureSemantics();
          expect(
            find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.liveRegion == true,
            ),
            findsOneWidget,
          );
          expect(
            find.semantics.byPredicate(
              (node) =>
                  !node.isMergedIntoParent &&
                  node.getSemanticsData().label == 'Keep focusing',
            ),
            isSemantics(
              label: 'Keep focusing',
              isButton: true,
              hasEnabledState: true,
              isEnabled: true,
              isFocusable: true,
              hasTapAction: true,
            ),
          );
          await tester.tap(_button('Keep focusing'));
          await tester.pump();
          expect(commands.calls, ['cancelExit']);
          commands.emit(
            const DistractionSettingsState(
              available: true,
              active: true,
              local: true,
              strict: true,
              strictExitSeconds: 60,
              exitPending: true,
              exitRemaining: 12,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(
              'Exit available in 12 seconds. You can cancel and return to Focus.',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('37 seconds'), findsNothing);
          semantics.dispose();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('immediate strict exit needs an explicit keyboard confirmation', (
    tester,
  ) async {
    final commands = _Commands(
      const DistractionSettingsState(
        available: true,
        active: true,
        strict: true,
        strictExitSeconds: 0,
        exitPending: true,
      ),
    );
    await _mount(
      tester,
      commands,
      const FocusExitHost(child: SizedBox.expand()),
      reduceMotion: true,
    );
    expect(
      find.text(
        'The interval will be interrupted without a completion reward.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Exit available in'), findsNothing);
    expect(commands.calls, isEmpty);
    final semantics = tester.ensureSemantics();
    expect(
      find.semantics.byPredicate(
        (node) =>
            !node.isMergedIntoParent &&
            node.getSemanticsData().label == 'Confirm exit',
      ),
      isSemantics(
        label: 'Confirm exit',
        isButton: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(commands.calls, ['confirmExit']);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed profile save keeps the draft and supports retry', (
    tester,
  ) async {
    final commands = _Commands(
      DistractionSettingsState(
        available: true,
        profiles: [_work],
        profileId: 'work',
      ),
    )..saveError = StateError('Save failed');
    await _mount(
      tester,
      commands,
      _settings(),
      brightness: Brightness.dark,
      reduceMotion: true,
    );
    await tester.tap(_button('Edit profile'));
    await tester.pumpAndSettle();
    final name = find.descendant(
      of: find.byType(ShadInput),
      matching: find.byType(EditableText),
    );
    await tester.enterText(name, 'Retained draft');
    await tester.tap(_button('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Save failed'), findsOneWidget);
    expect(tester.widget<EditableText>(name).controller.text, 'Retained draft');
    expect(commands.profiles, isEmpty);
    commands.saveError = null;
    await tester.tap(_button('Save'));
    await tester.pumpAndSettle();
    expect(commands.profiles.single.name, 'Retained draft');
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'resource corrections remain manual and exceptions target the selected profile',
    (tester) async {
      final commands = _Commands(
        DistractionSettingsState(
          available: true,
          profiles: [_work],
          profileId: 'work',
          assignments: [_youtube],
        ),
      );
      await _mount(
        tester,
        commands,
        _settings(),
        brightness: Brightness.dark,
        reduceMotion: true,
      );
      final category = find.byType(DropdownButtonFormField<String>).at(1);
      await tester.ensureVisible(category);
      await tester.tap(category);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Education').last);
      await tester.pumpAndSettle();
      expect(commands.assignments.single.id, 'youtube.com');
      expect(commands.assignments.single.category, 'education');
      expect(commands.assignments.single.source, 'manual');
      final exception = find.byType(DropdownButtonFormField<String>).at(2);
      await tester.ensureVisible(exception);
      await tester.tap(exception);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Always allow').last);
      await tester.pumpAndSettle();
      expect(commands.profiles.single.id, 'work');
      expect(commands.profiles.single.overrides, [
        {'kind': 'domain', 'id': 'youtube.com', 'action': 'allow'},
      ]);
      await tester.ensureVisible(_button('Find category · Pro'));
      await tester.tap(_button('Find category · Pro'));
      await tester.pump();
      expect(commands.calls, ['classify:youtube.com']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'active Focus locks policy selection while conflict actions remain explicit',
    (tester) async {
      final commands = _Commands(
        DistractionSettingsState(
          available: true,
          profiles: [_work],
          profileId: 'work',
          active: true,
          conflict: true,
          local: true,
        ),
      );
      await _mount(tester, commands, _settings(), width: 1200);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>).first,
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<int>>(
              find.byType(DropdownButtonFormField<int>),
            )
            .onChanged,
        isNull,
      );
      await tester.ensureVisible(_button('Join shared Focus'));
      await tester.tap(_button('Join shared Focus'));
      await tester.pump();
      await tester.tap(_button('Finish local Focus'));
      await tester.pump();
      await tester.ensureVisible(_button('End Focus on all devices'));
      await tester.tap(_button('End Focus on all devices'));
      await tester.pump();
      expect(commands.calls, ['joinShared', 'finishLocal', 'requestExit']);
      expect(commands.configurations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Escape dismisses a profile draft without saving', (
    tester,
  ) async {
    final commands = _Commands(
      DistractionSettingsState(
        available: true,
        profiles: [_work],
        profileId: 'work',
      ),
    );
    await _mount(tester, commands, _settings(), reduceMotion: true);
    await tester.tap(_button('Edit profile'));
    await tester.pumpAndSettle();
    final name = find.descendant(
      of: find.byType(ShadInput),
      matching: find.byType(EditableText),
    );
    await tester.enterText(name, 'Discarded draft');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(commands.profiles, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unavailable protection renders neither settings nor local badge',
    (tester) async {
      final commands = _Commands(const DistractionSettingsState());
      await _mount(
        tester,
        commands,
        const FocusExitHost(child: Scaffold(body: DistractionSettings())),
      );
      expect(find.text('Distraction blocking'), findsNothing);
      expect(find.byType(Chip), findsNothing);
      expect(find.text('End strict Focus?'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
