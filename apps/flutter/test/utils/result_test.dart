import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  test(
    'captures asynchronous errors and preserves their stack on rethrow',
    () async {
      final original = StateError('write failed');
      final trace = StackTrace.current;
      final result = await Result.capture<int>(
        () => Future<int>.error(original, trace),
      );
      expect(result, isA<Failure<int>>());
      try {
        result.getOrThrow();
        fail('The failed operation must not become a successful transaction.');
      } catch (error, stack) {
        expect(error, same(original));
        expect(stack.toString(), trace.toString());
      }
      expect((await Result.capture(() async => 42)).getOrThrow(), 42);
    },
  );
}
