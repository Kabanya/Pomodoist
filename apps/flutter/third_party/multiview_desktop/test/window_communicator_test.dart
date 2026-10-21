import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/impl/window_communicator_impl.dart';

void main() {
  group('WindowCommunicatorImpl', () {
    late WindowCommunicatorImpl communicator;

    setUp(() {
      communicator = WindowCommunicatorImpl();
    });

    tearDown(() async {
      await communicator.dispose();
    });

    test('broadcast delivers message to all subscribers', () async {
      final messages = <dynamic>[];
      final sub1 = communicator.onBroadcast.listen(messages.add);
      final sub2 = communicator.onBroadcast.listen(messages.add);

      communicator.broadcast({'theme': 'dark'});
      await Future<void>.delayed(Duration.zero);

      expect(messages, [
        {'theme': 'dark'},
        {'theme': 'dark'},
      ]);
      await sub1.cancel();
      await sub2.cancel();
    });

    test('send does not throw when no listener is subscribed', () {
      expect(() => communicator.send(99, 'orphan'), returnsNormally);
    });

    test('dispose completes without error', () async {
      final sub = communicator.onBroadcast.listen((_) {});
      await communicator.dispose();
      await sub.cancel();
    });
  });
}
