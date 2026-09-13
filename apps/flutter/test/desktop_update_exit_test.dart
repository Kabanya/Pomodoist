import 'dart:async';
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/updates/update_installer_io.dart';

class _ExitTestBinding extends AutomatedTestWidgetsFlutterBinding {
  final exitRequests = <(AppExitType, int)>[];

  @override
  Future<AppExitResponse> exitApplication(
    AppExitType exitType, [
    int exitCode = 0,
  ]) async {
    exitRequests.add((exitType, exitCode));
    // Match Windows' provisional cancel acknowledgement, without closing tests.
    return exitType == AppExitType.required
        ? AppExitResponse.exit
        : AppExitResponse.cancel;
  }
}

void main() {
  final binding = _ExitTestBinding();
  final calls = binding.exitRequests;
  late NativeUpdateInstaller installer;

  setUp(() {
    calls.clear();
    installer = NativeUpdateInstaller();
  });
  tearDown(() {
    installer.dispose();
  });

  test(
    'waits for app consent, then requests required native exit once',
    () async {
      final decision = Completer<AppExitResponse>();
      final consulted = Completer<void>();
      final listener = AppLifecycleListener(
        onExitRequested: () {
          consulted.complete();
          return decision.future;
        },
      );
      addTearDown(listener.dispose);
      final exiting = installer.requestUpdateExit();
      await Future<void>.delayed(Duration.zero);
      expect(consulted.isCompleted, isTrue);
      expect(calls, isEmpty);
      decision.complete(AppExitResponse.exit);
      expect(await exiting, AppExitResponse.exit);
      expect(calls, [(AppExitType.required, 0)]);
    },
  );

  test('an app veto never requests native exit', () async {
    final listener = AppLifecycleListener(
      onExitRequested: () async => AppExitResponse.cancel,
    );
    addTearDown(listener.dispose);
    expect(await installer.requestUpdateExit(), AppExitResponse.cancel);
    expect(calls, isEmpty);
  });

  test('disposal while waiting for consent cancels native exit', () async {
    final decision = Completer<AppExitResponse>();
    final listener = AppLifecycleListener(
      onExitRequested: () => decision.future,
    );
    addTearDown(listener.dispose);
    final exiting = installer.requestUpdateExit();
    installer.dispose();
    decision.complete(AppExitResponse.exit);
    expect(await exiting, AppExitResponse.cancel);
    expect(calls, isEmpty);
  });
}
