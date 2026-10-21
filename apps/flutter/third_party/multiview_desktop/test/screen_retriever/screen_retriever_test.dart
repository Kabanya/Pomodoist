import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/screen_retriever/screen_retriever.dart';

void main() {
  group('ScreenRetriever', () {
    const methodChannel = MethodChannel('multiview_desktop/screen_retriever');

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
    });

    test('getCursorScreenPoint returns logical offset', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannel,
        (call) async {
          expect(call.method, 'getCursorScreenPoint');
          expect(call.arguments, isA<Map>());
          return {'dx': 120.5, 'dy': 340.0};
        },
      );

      final point = await ScreenRetriever.instance.getCursorScreenPoint();
      expect(point, const Offset(120.5, 340));
    });

    test('getPrimaryDisplay parses display from native response', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannel,
        (call) async {
          if (call.method == 'getPrimaryDisplay') {
            return {
              'id': 'primary',
              'size': {'width': 1440.0, 'height': 900.0},
            };
          }
          return null;
        },
      );

      final display = await ScreenRetriever.instance.getPrimaryDisplay();
      expect(display.id, 'primary');
      expect(display.size.width, 1440);
    });

    test('getAllDisplays returns list of displays', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannel,
        (call) async {
          if (call.method == 'getAllDisplays') {
            return {
              'displays': [
                {
                  'id': 'a',
                  'size': {'width': 100.0, 'height': 100.0},
                },
                {
                  'id': 'b',
                  'size': {'width': 200.0, 'height': 200.0},
                },
              ],
            };
          }
          return null;
        },
      );

      final displays = await ScreenRetriever.instance.getAllDisplays();
      expect(displays, hasLength(2));
      expect(displays.first.id, 'a');
    });

    test('getCursorScreenPoint throws when native returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannel,
        (_) async => null,
      );

      expect(
        ScreenRetriever.instance.getCursorScreenPoint(),
        throwsA(isA<Exception>()),
      );
    });

    test('addListener and removeListener manage subscription lifecycle', () async {
      final listener = _RecordingScreenListener();
      final retriever = ScreenRetriever.instance;

      retriever.addListener(listener);
      expect(retriever.hasListeners, isTrue);

      retriever.removeListener(listener);
      expect(retriever.hasListeners, isFalse);
    });
  });
}

class _RecordingScreenListener with ScreenListener {
  final events = <String>[];

  @override
  void onScreenEvent(String eventName) => events.add(eventName);
}
