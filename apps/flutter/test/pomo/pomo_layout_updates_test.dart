import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/pomo/widgets/pomo_layout_updates.dart';

void main() {
  test(
    'native changes serialize and keep only the latest queued layout',
    () async {
      final gate = Completer<void>();
      final values = <int>[];
      var latest = 1, active = 0;
      final updates = PomoLayoutUpdates(() async {
        expect(++active, 1);
        values.add(latest);
        if (values.length == 1) await gate.future;
        active--;
      });
      final first = updates.request();
      latest = 2;
      updates.request();
      latest = 3;
      final last = updates.request();
      gate.complete();
      await Future.wait([first, last]);
      expect(values, [1, 3]);
      expect(updates.running, false);
      latest = 4;
      await updates.request();
      expect(values, [1, 3, 4]);
    },
  );
  test('a failed native transaction releases the queue for retry', () async {
    var fail = true;
    final updates = PomoLayoutUpdates(() async {
      if (fail) throw StateError('native');
    });
    await expectLater(updates.request(), throwsStateError);
    expect(updates.running, false);
    fail = false;
    await updates.request();
  });
}
