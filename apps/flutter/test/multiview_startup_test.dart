import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/view_root.dart';

class _LateDispatcher extends TestPlatformDispatcher {
  _LateDispatcher(ui.PlatformDispatcher dispatcher)
    : super(platformDispatcher: dispatcher);
  bool attached = false;
  late final window = _Window(
    view: implicitView!,
    platformDispatcher: this,
    display: displays.first,
  );
  @override
  Iterable<TestFlutterView> get views => attached ? [window] : [];
  @override
  ui.FlutterView? view({required int id}) =>
      attached && id == window.viewId ? window : null;
}

class _Window extends TestFlutterView {
  _Window({
    required super.view,
    required super.platformDispatcher,
    required super.display,
  });
  @override
  int get viewId => 1;
}

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  late final dispatcher = _LateDispatcher(super.platformDispatcher);
  @override
  TestPlatformDispatcher get platformDispatcher => dispatcher;
}

void main() {
  final binding = _Binding();
  testWidgets('native startup errors reach the bootstrap caller', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('multiview_desktop'),
      (call) async {
        throw PlatformException(code: 'window-startup');
      },
    );
    await expectLater(
      Future<void>.sync(
        () => runMultiApp(home: (context, id) => const SizedBox()),
      ),
      throwsA(isA<PlatformException>()),
    );
  });

  testWidgets('initial window registration errors reach the bootstrap caller', (
    tester,
  ) async {
    binding.dispatcher.attached = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('multiview_desktop'),
      (call) async {
        if (call.method == 'checkExistViewId') return true;
        if (call.method == 'setTitle') {
          throw PlatformException(code: 'initial-window');
        }
        return null;
      },
    );
    final failure = expectLater(
      runMultiApp(
        home: (context, id) => const SizedBox(),
        config: MultiAppConfig(
          globalWindowOptions: const WindowOptions(title: 'Tasks'),
        ),
      ),
      throwsA(isA<PlatformException>()),
    );
    await tester.pumpAndSettle();
    await failure;
    await tester.pumpWidget(
      const ViewCollection(views: []),
      wrapWithView: false,
    );
    binding.dispatcher.attached = false;
  });

  testWidgets('an initial window attached after startup renders exactly once', (
    tester,
  ) async {
    var shows = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('multiview_desktop'),
      (call) async {
        if (call.method == 'checkExistViewId') {
          return binding.dispatcher.attached;
        }
        if (call.method == 'show') shows++;
        return null;
      },
    );
    final root = await createMultiViewRoot(
      (context, id) => const MaterialApp(home: Text('Tasks ready')),
      null,
      MultiAppConfig(),
    );
    await tester.pumpWidget(root, wrapWithView: false);
    expect(find.text('Tasks ready'), findsNothing);

    binding.dispatcher.attached = true;
    for (var event = 0; event < 1000; event++) {
      binding.handleMetricsChanged();
    }
    await tester.pumpAndSettle();
    expect(find.text('Tasks ready'), findsOneWidget);
    expect(shows, 1);
    binding.handleMetricsChanged();
    await tester.pumpAndSettle();
    expect(shows, 1);
    await tester.pumpWidget(
      const ViewCollection(views: []),
      wrapWithView: false,
    );
  });
}
