import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/native_channel.dart';

void main() {
  group('NativeChannel.setTaskbarMenu', () {
    const methodChannel = MethodChannel('multiview_desktop');

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
    });

    test('invokes setTaskbarMenu with items payload', () async {
      Map<dynamic, dynamic>? capturedArguments;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        methodChannel,
        (call) async {
          expect(call.method, kMethodSetTaskbarMenu);
          capturedArguments = call.arguments as Map<dynamic, dynamic>?;
          return null;
        },
      );

      await NativeChannel().setTaskbarMenu([
        {'id': 0, 'title': 'Open new window'},
        {'id': 1, 'title': 'Settings', 'icon': 'base64-data'},
      ]);

      expect(capturedArguments, isNotNull);
      final items = capturedArguments!['items'] as List<dynamic>;
      expect(items, hasLength(2));
      expect(items[0], {'id': 0, 'title': 'Open new window'});
      expect(items[1], {
        'id': 1,
        'title': 'Settings',
        'icon': 'base64-data',
      });
    });
  });
}
