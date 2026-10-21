import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/impl/cascade_close_service_impl.dart';

void main() {
  group('CascadeCloseService', () {
    late CascadeCloseService service;

    setUp(() => service = CascadeCloseService());

    test('waitWindow returns true when window completes', () async {
      service.attachWindow(1);
      service.completeWindow(1);

      expect(await service.waitWindow(1), isTrue);
    });

    test('waitWindow returns false when cascade is aborted while waiting', () async {
      service.attachWindow(1);
      service.attachWindow(2);

      final wait1 = service.waitWindow(1);
      final wait2 = service.waitWindow(2);
      service.abort(1);

      expect(await wait1, isFalse);
      expect(await wait2, isFalse);
    });

    test('abort clears pending completers', () async {
      service.attachWindow(10);
      final wait = service.waitWindow(10);
      service.abort(10);

      expect(await wait, isFalse);
      service.clear();
    });

    test('detachWindow removes completer without completing', () async {
      service.attachWindow(5);
      service.detachWindow(5);

      expect(await service.waitWindow(5), isTrue);
    });
  });
}
