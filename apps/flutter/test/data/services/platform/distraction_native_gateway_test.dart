import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/platform/distraction_native_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/distractions');
  final binding =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => binding.setMockMethodCallHandler(channel, null));

  test('rejects private paths and malformed foreground identities', () {
    expect(
      DistractionNativeApp.fromNative({
        'id': 'macos:/Applications/Chat.app',
        'name': 'Chat',
        'platform': 'macos',
      }),
      isNull,
    );
    expect(
      DistractionNativeApp.fromNative({
        'id': 'windows:C:\\Chat.exe',
        'name': 'Chat',
        'platform': 'windows',
      }),
      isNull,
    );
    expect(
      DistractionNativeApp.fromNative({
        'id': 'linux:Chat',
        'name': 'Chat',
        'platform': 'macos',
      }),
      isNull,
    );
    expect(
      DistractionNativeApp.fromNative({
        'id': 'linux:',
        'name': 'Chat',
        'platform': 'linux',
      }),
      isNull,
    );
    expect(
      DistractionNativeApp.fromNative({
        'id': 'macos:com.example.Chat',
        'name': 'Chat',
        'platform': 'macos',
      })?.id,
      'macos:com.example.Chat',
    );
  });

  test(
    'delivers typed callbacks and quit requests without private fields',
    () async {
      binding.setMockMethodCallHandler(channel, (call) async => null);
      final gateway = DistractionNativeGateway(channel: channel);
      const codec = StandardMethodCodec();
      void emit(String method, Object? arguments) {
        ServicesBinding.instance.channelBuffers.push(
          channel.name,
          codec.encodeMethodCall(MethodCall(method, arguments)),
          (_) {},
        );
      }

      final foreground = gateway.foregroundApps.first;
      emit('foregroundApp', {
        'id': 'macos:com.example.Chat',
        'name': 'Chat',
        'platform': 'macos',
        'windowTitle': 'PRIVATE',
      });
      expect((await foreground).id, 'macos:com.example.Chat');
      final attempt = gateway.blockedAttempts.first;
      emit('blockedAttempt', {
        'id': 'linux:org.example.Chat',
        'name': 'Chat',
        'platform': 'linux',
      });
      expect((await attempt).name, 'Chat');
      final quit = gateway.quitRequests.first;
      emit('requestQuit', null);
      await quit;
      await gateway.allowQuit();
      await gateway.dispose();
    },
  );

  test('missing plugin reports actual unsupported capability', () async {
    final gateway = DistractionNativeGateway(channel: channel);
    expect((await gateway.capabilities()).supported, isFalse);
    await gateway.dispose();
  });

  test(
    'forwards bounded protection and clears native lifetime resources',
    () async {
      final calls = <MethodCall>[];
      binding.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'capabilities') {
          return {
            'supported': true,
            'platform': 'macos',
            'discoveryAvailable': true,
          };
        }
        return null;
      });
      final gateway = DistractionNativeGateway(channel: channel);
      await gateway.startDiscovery();
      await gateway.setProtection(
        active: true,
        blockedApps: ['macos:com.example.Chat'],
        taskTitle: 'Write',
        remainingSeconds: 60,
        expiresAt: DateTime.utc(2026, 10, 26),
      );
      expect(calls.last.arguments['expiresAt'], '2026-10-26T00:00:00.000Z');
      await gateway.dispose();
      expect(calls.map((call) => call.method), [
        'startDiscovery',
        'setProtection',
        'clearProtection',
        'stopDiscovery',
      ]);
    },
  );
}
