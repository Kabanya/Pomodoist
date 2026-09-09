import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/theme/macos_glass.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pomodoist/macos_glass');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ProviderContainer container;
  late MacosGlassController controller;
  late List<Object> events;

  setUp(() {
    events = [];
    container = ProviderContainer(
      overrides: [
        macosGlassOpaqueFrameProvider.overrideWithValue((duration) async {
          events.add('opaque');
        }),
      ],
    );
    controller = container.read(macosGlassProvider.notifier);
    messenger.setMockMethodCallHandler(channel, (call) async {
      events.add(call.arguments);
      return {
        'enabled': (call.arguments as Map)['enabled'],
        'reduceTransparency': false,
      };
    });
  });
  tearDown(() {
    container.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'per-view enabling waits for acknowledgement and disabling waits for paint',
    () async {
      final reply = Completer<Object>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        events.add(call.arguments);
        return reply.future;
      });
      final pending = controller.update(42, enabled: true, dark: true);
      expect(container.read(macosGlassProvider)[42], isNot(true));
      reply.complete({'enabled': true, 'reduceTransparency': false});
      await pending;
      expect(container.read(macosGlassProvider)[42], isTrue);
      messenger.setMockMethodCallHandler(channel, (call) async {
        events.add(call.arguments);
        return {'enabled': false, 'reduceTransparency': false};
      });
      final disable = controller.update(42, enabled: false, dark: true);
      expect(container.read(macosGlassProvider)[42], isFalse);
      await disable;
      expect(events, [
        {'viewId': 42, 'enabled': true, 'dark': true},
        'opaque',
        {'viewId': 42, 'enabled': false, 'dark': true},
      ]);
      await controller.update(99, enabled: true, dark: false);
      expect(events.last, {'viewId': 99, 'enabled': true, 'dark': false});
    },
  );

  test(
    'stale replies cannot undo cancellation and calls stay ordered',
    () async {
      final reply = Completer<Object>();
      final started = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        events.add(call.arguments);
        if ((call.arguments as Map)['enabled'] == true) {
          started.complete();
          return reply.future;
        }
        return {'enabled': false, 'reduceTransparency': false};
      });
      final enable = controller.update(7, enabled: true, dark: false);
      await started.future;
      final disable = controller.update(7, enabled: false, dark: false);
      reply.complete({'enabled': true, 'reduceTransparency': false});
      await Future.wait([enable, disable]);
      expect(container.read(macosGlassProvider)[7], isFalse);
      expect((events.last as Map)['enabled'], isFalse);
    },
  );

  test(
    'missing channel, native error and malformed reply keep a solid background',
    () async {
      for (final failure in [
        null,
        PlatformException(code: 'window_missing'),
        'bad',
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async {
          if (failure is PlatformException) throw failure;
          return failure;
        });
        await controller.update(1, enabled: true, dark: false);
        expect(container.read(macosGlassProvider)[1], isNot(true));
        controller.forget(1);
      }
    },
  );

  test(
    'transparency notifications restore every live window using its brightness',
    () async {
      await controller.update(3, enabled: true, dark: false);
      await controller.update(8, enabled: true, dark: true);
      Future<void> notify(bool reduced) async {
        final done = Completer<void>();
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('transparencyChanged', {'reduceTransparency': reduced}),
          ),
          (_) => done.complete(),
        );
        await done.future;
      }

      await notify(true);
      expect(container.read(macosGlassProvider).values, everyElement(false));
      controller.forget(8);
      events.clear();
      await notify(false);
      expect(container.read(macosGlassProvider)[3], isTrue);
      expect(container.read(macosGlassProvider).containsKey(8), isFalse);
      expect(events, [
        {'viewId': 3, 'enabled': true, 'dark': false},
      ]);
    },
  );

  test('closing a window discards its late acknowledgement', () async {
    final reply = Completer<Object>();
    final started = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (_) {
      started.complete();
      return reply.future;
    });
    final pending = controller.update(5, enabled: true, dark: false);
    await started.future;
    controller.forget(5);
    reply.complete({'enabled': true, 'reduceTransparency': false});
    await pending;
    expect(container.read(macosGlassProvider).containsKey(5), isFalse);
  });
}
