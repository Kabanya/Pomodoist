// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/window_lifecycle_policy.dart';

void main() {
  test(
    'Linux secondary focus resumes keyboard lifecycle; external focus stays inactive',
    () async {
      var state = AppLifecycleState.inactive;
      var focused = true;
      final lifecycle = LinuxWindowLifecycle(
        hasFocusedWindow: () async => focused,
        readState: () => state,
        applyState: (next) => state = next,
      );
      await lifecycle.synchronize();
      expect(state, AppLifecycleState.resumed);
      focused = false;
      await lifecycle.synchronize();
      expect(state, AppLifecycleState.inactive);
      await lifecycle.synchronize();
      expect(state, AppLifecycleState.inactive);
      lifecycle.dispose();
    },
  );

  test(
    'Linux lifecycle rejects stale focus replies and disposed work',
    () async {
      var state = AppLifecycleState.inactive;
      final replies = <Completer<bool>>[];
      final lifecycle = LinuxWindowLifecycle(
        hasFocusedWindow: () {
          final reply = Completer<bool>();
          replies.add(reply);
          return reply.future;
        },
        readState: () => state,
        applyState: (next) => state = next,
      );
      final first = lifecycle.synchronize(), second = lifecycle.synchronize();
      replies[1].complete(false);
      await second;
      replies[0].complete(true);
      await first;
      expect(state, AppLifecycleState.inactive);
      final closing = lifecycle.synchronize();
      lifecycle.dispose();
      replies[2].complete(true);
      await closing;
      expect(state, AppLifecycleState.inactive);
    },
  );
  testWidgets(
    'hidden desktop windows notify lifecycle listeners before resuming',
    (tester) async {
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final states = <AppLifecycleState>[];
      final keeper = AppLifecycleListener(
        onHide: () => keepDesktopFramesAlive(() => true),
      );
      final listener = AppLifecycleListener(onStateChange: states.add);
      addTearDown(keeper.dispose);
      addTearDown(listener.dispose);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.idle();
      expect(states.last, AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(states.last, AppLifecycleState.resumed);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deferred rendering does not revive closed or foreground windows',
    (tester) async {
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var hasWindows = true;
      final keeper = AppLifecycleListener(
        onHide: () => keepDesktopFramesAlive(() => hasWindows),
      );
      addTearDown(keeper.dispose);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      hasWindows = false;
      await tester.idle();
      expect(binding.lifecycleState, AppLifecycleState.hidden);

      hasWindows = true;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.idle();
      expect(binding.lifecycleState, AppLifecycleState.resumed);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Pomo and Quick Add cannot replace the main window, even while hidden',
    () {
      const windows = [
        (id: 1, parentId: null),
        (id: 2, parentId: null),
        (id: 3, parentId: null),
        (id: 4, parentId: 1),
      ];
      expect(
        appWindowCandidates(
          windows: windows,
          utilityIds: {2, 3},
          liveIds: {1, 2, 3, 4},
        ),
        [1],
      );
      // An empty list activates macOS retain-main behavior and Windows utility cleanup.
      expect(
        appWindowCandidates(
          windows: windows,
          utilityIds: {2, 3},
          liveIds: {1, 2, 3, 4},
          excludingId: 1,
        ),
        isEmpty,
      );
      expect(
        appWindowCandidates(
          windows: windows,
          utilityIds: {2, 3},
          liveIds: {2, 3, 4},
        ),
        isEmpty,
      );
    },
  );
}
