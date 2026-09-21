import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A test double with an "only what the test stubbed explicitly is stubbed"
/// policy.
///
/// Any unstubbed member throws [UnimplementedError] naming itself, instead of
/// the context-free `NoSuchMethodError` that [Fake] would raise.
///
/// Use it for doubles of interfaces:
///
/// ```dart
/// class FakeThing extends StrictFake implements Thing {
///   @override
///   String get name => 'stubbed';
/// }
/// ```
///
/// Doubles of concrete classes cannot use this base — they must extend the
/// class under test instead. See [FakeNotifier] for the `Notifier<T>` case.
abstract class StrictFake extends Fake {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      '$runtimeType.${invocation.memberName} is not stubbed',
    );
  }
}

/// Base for doubles of `Notifier<T>` providers.
///
/// `Notifier<T>` occupies the `extends` slot, so the [Fake] mixin is applied
/// with `with` rather than through [StrictFake]. Subclasses override [build]
/// to supply the initial state.
abstract class FakeNotifier<T> extends Notifier<T> with Fake {}
