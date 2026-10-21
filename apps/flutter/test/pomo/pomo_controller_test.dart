import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/pomo_dependencies.dart' as composition;
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/data/repositories/pomo/pomo_preferences_repository_impl.dart';
import 'package:pomodoist/domain/models/pomo/pomo_models.dart';
import 'package:pomodoist/domain/models/pomo/pomo_focus.dart';
import 'package:pomodoist/domain/models/pomo/pomo_reactions.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/tasks/local_completion_event.dart';
import 'package:pomodoist/ui/pomo/view_models/pomo_controller.dart';
import 'package:pomodoist/utils/result.dart';

class MemoryPreferences extends PreferencesService {
  MemoryPreferences() : super(() async => null);
  final values = <String, Object>{};
  Completer<void>? gate;
  bool fail = false;
  bool failRead = false;
  @override
  Future<Result<Map<String, Object>>> read(
    Iterable<String> keys, {
    bool reload = false,
  }) => Result.capture(() async {
    if (failRead) throw StateError('read failed');
    return {...values};
  });
  @override
  Future<Result<void>> write(Map<String, Object?> changes) =>
      Result.capture(() async {
        await gate?.future;
        if (fail) throw StateError('write failed');
        for (final e in changes.entries) {
          if (e.value == null) {
            values.remove(e.key);
          } else {
            values[e.key] = e.value!;
          }
        }
      });
}

class Host implements PomoHost {
  int shows = 0, hides = 0, panels = 0, menus = 0;
  bool panel = false;
  bool capsuleVisible = true;
  @override
  Future<void> setCapsuleVisible(bool value) async {
    capsuleVisible = value;
  }

  double scale = 1;
  @override
  Future<void> setScale(double value) async {
    scale = value;
  }

  @override
  Future<void> openSettings() async {
    panels++;
    panel = true;
  }

  @override
  Future<void> closeSettings() async {
    panel = false;
  }

  bool fail = false;
  @override
  Future<void> show(PomoPreferences preferences) async {
    if (fail) throw StateError('native failure');
    shows++;
  }

  @override
  Future<void> hide() async {
    hides++;
  }

  @override
  Future<void> resetPosition() async {}
  @override
  Future<void> setMenu(bool expanded) async {
    menus++;
  }
}

FocusRunItem run() => FocusRunItem(
  id: 'r',
  userId: 'u',
  presetId: 'p',
  status: 'active',
  startedAt: DateTime(2026),
  targetWorkIntervals: 1,
  completedWorkIntervals: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
void main() {
  test(
    'composition shares the Pomo controller without opening a window',
    () async {
      final prefs = LocalPomoPreferencesRepository(MemoryPreferences());
      final container = ProviderContainer(
        overrides: [
          ...composition.pomoOverrides,
          composition.pomoPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(prefs.dispose);
      addTearDown(container.dispose);
      final controller = container.read(pomoControllerProvider);
      expect(container.read(pomoControllerProvider), same(controller));
      expect(controller.preferences, same(prefs));
      await controller.changeScale(1.2);
      expect(container.read(pomoControllerProvider).scale, 1.2);
      expect(prefs.state.enabled, false);
      expect(
        container.read(pomoActionsProvider).completeInterval,
        isA<Function>(),
      );
      expect(controller.visible, false);
    },
  );

  test(
    'timer visibility persists and updates the host without reopening',
    () async {
      final service = MemoryPreferences();
      final prefs = LocalPomoPreferencesRepository(service), host = Host();
      final c = PomoController(prefs, host);
      addTearDown(prefs.dispose);
      addTearDown(c.dispose);
      await c.initialize();
      await c.restore();
      await c.tap(react: false);
      final shows = host.shows;
      service.gate = Completer<void>();
      final saving = c.updatePreferences((p) => p.copyWith(showTimer: false));
      await Future<void>.delayed(Duration.zero);
      expect(c.prefs.showTimer, true);
      expect(host.capsuleVisible, true);
      service.gate!.complete();
      await saving;
      expect(c.prefs.showTimer, false);
      expect(host.capsuleVisible, false);
      expect(c.capsuleVisible, false);
      expect(c.menu, true);
      expect(host.shows, shows);
      final loaded = LocalPomoPreferencesRepository(service);
      addTearDown(loaded.dispose);
      await loaded.load();
      expect(loaded.state.showTimer, false);

      service.fail = true;
      await c.updatePreferences((p) => p.copyWith(showTimer: true));
      expect(c.prefs.showTimer, false);
      expect(c.error, isNotNull);
      expect(c.capsuleVisible, true);
      expect(host.capsuleVisible, true);
      service.fail = false;
      await c.updatePreferences((p) => p.copyWith(quiet: true));
      expect(c.error, isNull);
      expect(host.capsuleVisible, false);
      await c.updatePreferences((p) => p.copyWith(showTimer: true));
      expect(host.capsuleVisible, true);
      expect(c.menu, true);
      expect(host.shows, shows);
    },
  );
  test(
    'unchanged applied size and collapsed menu do not refresh every window',
    () async {
      final prefs = LocalPomoPreferencesRepository(MemoryPreferences()),
          host = Host();
      final c = PomoController(prefs, host);
      await c.initialize();
      var notifications = 0;
      c.addListener(() => notifications++);
      c.appliedScale(1);
      await c.collapse();
      expect(notifications, 0);
      expect(host.menus, 0);
      c.appliedScale(1.25);
      expect(notifications, 1);
      c.appliedScale(1.25);
      expect(notifications, 1);
      c.dispose();
      prefs.dispose();
    },
  );

  test(
    'returning to saved scale queues behind an unfinished earlier write',
    () async {
      final service = MemoryPreferences();
      final prefs = LocalPomoPreferencesRepository(service);
      final c = PomoController(prefs, Host());
      await c.initialize();
      service.gate = Completer<void>();
      final first = c.changeScale(1.05);
      final last = c.changeScale(1);
      service.gate!.complete();
      await Future.wait([first, last]);
      expect(c.scale, 1);
      expect(prefs.state.scale, 1);
      c.dispose();
      prefs.dispose();
    },
  );

  test(
    'two size observers share preview, commit, rollback and disabled state',
    () async {
      final service = MemoryPreferences();
      final prefs = LocalPomoPreferencesRepository(service), host = Host();
      final c = PomoController(prefs, host);
      await c.initialize();
      final first = <double>[], second = <double>[];
      c.addListener(() => first.add(c.scale));
      c.addListener(() => second.add(c.scale));
      c.previewScale(1.65);
      expect(c.scale, 1.65);
      expect(prefs.state.scale, 1);
      await c.commitScale();
      expect(prefs.state.scale, 1.65);
      expect(c.visible, false);
      expect(prefs.state.enabled, false);
      service.fail = true;
      c.previewScale(2.5);
      await c.commitScale();
      expect(c.scale, 1.65);
      expect(c.error, isNotNull);
      expect(first, second);
      service.fail = false;
      await c.changeScale(1);
      expect(c.error, isNull);
      expect(prefs.state.scale, 1);
      c.dispose();
      prefs.dispose();
    },
  );
  test(
    'panel opens once; close commits; hiding and disabling close it',
    () async {
      final prefs = LocalPomoPreferencesRepository(MemoryPreferences()),
          host = Host();
      final c = PomoController(prefs, host);
      await c.initialize();
      await c.restore();
      await Future.wait([c.openSettings(), c.openSettings()]);
      expect(host.panels, 1);
      expect(c.settingsOpen, true);
      c.previewScale(.45);
      await c.closeSettings();
      expect(prefs.state.scale, .45);
      expect(c.settingsOpen, false);
      expect(host.panel, false);
      await c.openSettings();
      await c.updatePreferences((p) => p.copyWith(quiet: true));
      await c.hideManually();
      expect(host.panel, false);
      await c.restore();
      await c.openSettings();
      await c.setEnabled(false);
      expect(host.panel, false);
      expect(c.settingsOpen, false);
      c.dispose();
      prefs.dispose();
    },
  );

  test('background transitions survive reactions, quiet mode and hiding', () {
    fakeAsync((time) {
      final preferences = LocalPomoPreferencesRepository(MemoryPreferences());
      final c = PomoController(
        preferences,
        Host(),
        reactions: PomoReactions(now: () => DateTime(2026).add(time.elapsed)),
      );
      FocusIntervalItem interval(String type, {String status = 'running'}) =>
          FocusIntervalItem(
            id: 'interval',
            runId: 'r',
            type: type,
            status: status,
            plannedSeconds: 3600,
            startedAt: DateTime(2026),
            pausedTotalSeconds: 0,
            sequenceNumber: 1,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          );
      c.initialize();
      time.flushMicrotasks();
      c.restore();
      time.flushMicrotasks();
      c.updateFocus(PomoFocus(run: run(), interval: interval('work')));
      time.elapse(const Duration(seconds: 3));
      expect(c.emotion, PomoEmotion.focus);
      expect(c.animated, true);
      c.completed(
        const LocalCompletionEvent(
          operationId: 'background-transition',
          entityId: 'task',
          isTask: true,
        ),
      );
      c.updateFocus(PomoFocus(run: run(), interval: interval('short_break')));
      expect(c.emotion, PomoEmotion.happy);
      time.elapse(const Duration(seconds: 3));
      expect(c.emotion, PomoEmotion.rest);
      c.updateFocus(
        PomoFocus(
          run: run(),
          interval: interval('work'),
          workSinceBreak: const Duration(minutes: 50),
        ),
      );
      expect(c.emotion, PomoEmotion.tired);
      c.updatePreferences((p) => p.copyWith(quiet: true));
      time.flushMicrotasks();
      expect(c.emotion, PomoEmotion.tired);
      expect(c.animated, false);
      c.setSystemMotion(true);
      c.updatePreferences((p) => p.copyWith(quiet: false));
      time.flushMicrotasks();
      expect(c.animated, false);
      c.setSystemMotion(false);
      expect(c.animated, true);
      c.updateFocus(
        PomoFocus(
          run: run(),
          interval: interval('work', status: 'paused'),
        ),
      );
      expect(c.emotion, PomoEmotion.calm);
      c.updatePreferences((p) => p.copyWith(enabled: false));
      time.elapse(const Duration(milliseconds: 100));
      expect(c.visible, false);
      expect(c.animated, false);
      c.dispose();
      preferences.dispose();
      time.flushMicrotasks();
    });
  });

  test(
    'enabling Reduce Motion during Sad removes the remaining close delay',
    () {
      fakeAsync((time) {
        final preferences = LocalPomoPreferencesRepository(MemoryPreferences());
        final c = PomoController(preferences, Host());
        c.initialize();
        time.flushMicrotasks();
        c.restore();
        time.flushMicrotasks();
        c.hideManually();
        time.elapse(const Duration(milliseconds: 100));
        expect(c.visible, true);
        c.setSystemMotion(true);
        time.elapse(Duration.zero);
        expect(c.visible, false);
        c.dispose();
        preferences.dispose();
        time.flushMicrotasks();
      });
    },
  );

  test('restore recovers from a failed startup preference read', () async {
    final service = MemoryPreferences()..failRead = true;
    final preferences = LocalPomoPreferencesRepository(service), host = Host();
    final c = PomoController(preferences, host);
    addTearDown(c.dispose);
    addTearDown(preferences.dispose);
    await c.initialize();
    expect(c.error, isNotNull);
    service.failRead = false;
    await c.restore();
    expect(c.visible, true);
    expect(host.shows, 1);
  });

  test(
    'show greets once, manual dismissal wins, hidden events are not replayed',
    () {
      fakeAsync((time) {
        final service = MemoryPreferences(), host = Host();
        final preferences = LocalPomoPreferencesRepository(service);
        final c = PomoController(
          preferences,
          host,
          reactions: PomoReactions(now: () => DateTime(2026).add(time.elapsed)),
        );
        c.initialize();
        time.flushMicrotasks();
        expect(host.shows, 0);
        c.restore();
        time.flushMicrotasks();
        expect(host.shows, 1);
        expect(c.emotion, PomoEmotion.greeting);
        c.updateFocus(PomoFocus(run: run()));
        time.elapse(const Duration(milliseconds: 100));
        expect(host.shows, 1);
        c.completed(
          const LocalCompletionEvent(
            operationId: 'a',
            entityId: 'a',
            isTask: true,
          ),
        );
        expect(c.emotion, PomoEmotion.happy);
        c.hideManually();
        c.hideManually();
        time.flushMicrotasks();
        expect(preferences.state.dismissed, true);
        expect(c.emotion, PomoEmotion.sad);
        time.elapse(const Duration(milliseconds: 899));
        expect(c.visible, true);
        time.elapse(const Duration(milliseconds: 1));
        expect(c.visible, false);
        c.completed(
          const LocalCompletionEvent(
            operationId: 'b',
            entityId: 'b',
            isTask: true,
          ),
        );
        c.updateFocus(PomoFocus(run: run()));
        time.elapse(const Duration(seconds: 5));
        expect(host.shows, 1);
        c.restore();
        time.flushMicrotasks();
        expect(host.shows, 2);
        expect(c.emotion, PomoEmotion.greeting);
        c.dispose();
        preferences.dispose();
        time.flushMicrotasks();
      });
    },
  );
  test(
    'focusOnly waits for celebration, quiet hide is immediate, failed host is visible as error',
    () {
      fakeAsync((time) {
        final preferences = LocalPomoPreferencesRepository(MemoryPreferences()),
            host = Host();
        final c = PomoController(
          preferences,
          host,
          reactions: PomoReactions(now: () => DateTime(2026).add(time.elapsed)),
        );
        c.initialize();
        time.flushMicrotasks();
        c.updatePreferences((p) => p.copyWith(enabled: true, focusOnly: true));
        time.elapse(const Duration(milliseconds: 100));
        expect(c.visible, false);
        c.updateFocus(PomoFocus(run: run()));
        time.elapse(const Duration(milliseconds: 100));
        expect(c.visible, true);
        c.completed(
          const LocalCompletionEvent(
            operationId: 'x',
            entityId: 'x',
            isTask: false,
          ),
        );
        c.updateFocus(const PomoFocus());
        time.elapse(const Duration(milliseconds: 100));
        expect(c.visible, true);
        time.elapse(const Duration(seconds: 3));
        expect(c.visible, false);
        host.fail = true;
        c.restore();
        time.flushMicrotasks();
        expect(c.visible, false);
        expect(c.error, isNotNull);
        host.fail = false;
        c.restore();
        time.flushMicrotasks();
        expect(c.visible, true);
        c.updatePreferences((p) => p.copyWith(quiet: true));
        time.flushMicrotasks();
        c.hideManually();
        time.elapse(Duration.zero);
        expect(c.visible, false);
        c.dispose();
        preferences.dispose();
        time.flushMicrotasks();
      });
    },
  );
  test(
    'preference writes serialize and failed writes do not replace state',
    () async {
      final service = MemoryPreferences();
      final prefs = LocalPomoPreferencesRepository(service);
      addTearDown(prefs.dispose);
      await Future.wait([
        prefs.update((p) => p.copyWith(enabled: true)),
        prefs.update((p) => p.copyWith(dismissed: true)),
      ]);
      expect(prefs.state.enabled, true);
      expect(prefs.state.dismissed, true);
      service.fail = true;
      await expectLater(
        prefs.update((p) => p.copyWith(dismissed: false)),
        throwsStateError,
      );
      expect(prefs.state.dismissed, true);
      service.fail = false;
      await prefs.update((p) => p.copyWith(quiet: true));
      final loaded = LocalPomoPreferencesRepository(service);
      addTearDown(loaded.dispose);
      await loaded.load();
      expect(loaded.state.dismissed, true);
      expect(loaded.state.quiet, true);
    },
  );
}
