import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/native_channel.dart';
import 'package:multiview_desktop/src/window_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('multiview_desktop');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'creation encodes passive layer surface and transparent backing before realization',
    () async {
      MethodCall? request;
      messenger.setMockMethodCallHandler(channel, (call) async {
        request = call;
        return null;
      });
      const options = WindowOptions(
        linuxDesktopOverlay: true,
        isUtility: true,
        focusOnShow: false,
        backgroundColor: Colors.transparent,
      );
      await NativeChannel().createWindowRequest(
        token: 41,
        title: 'Pomo',
        focusOnShow: options.focusOnShow!,
        isUtility: options.isUtility,
        linuxDesktopOverlay: options.linuxDesktopOverlay,
        backgroundColor: options.backgroundColor,
        titleBarStyleStr: 'hidden',
        windowButtonVisibility: false,
        windowSize: const Size(300, 320),
        pos: const Offset(-200, 40),
      );
      expect(request!.method, 'createWindow');
      expect(request!.arguments, containsPair('focusOnShow', false));
      expect(request!.arguments, containsPair('isUtility', true));
      expect(request!.arguments, containsPair('linuxDesktopOverlay', true));
      expect(request!.arguments, containsPair('backgroundColorA', 0));
      expect(
        request!.arguments,
        containsPair('position', {'x': -200.0, 'y': 40.0}),
      );
    },
  );

  test('ordinary windows retain normal native creation defaults', () async {
    Map<dynamic, dynamic>? args;
    messenger.setMockMethodCallHandler(channel, (call) async {
      args = call.arguments as Map<dynamic, dynamic>;
      return null;
    });
    await NativeChannel().createWindowRequest(
      token: 42,
      title: 'Main',
      titleBarStyleStr: 'normal',
      windowButtonVisibility: true,
      windowSize: const Size(800, 600),
      pos: null,
    );
    expect(args, containsPair('focusOnShow', true));
    expect(args, containsPair('isUtility', false));
    expect(args, containsPair('linuxDesktopOverlay', false));
    expect(args, isNot(contains('backgroundColorA')));
  });
}
