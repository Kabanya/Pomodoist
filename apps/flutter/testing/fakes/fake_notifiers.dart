import 'strict_fake.dart';

/// Double for a `NotifierProvider<..., bool>` whose state the test drives.
///
/// The provider starts at [initialValue]; [setValue] pushes a new value so the
/// widgets watching the provider rebuild.
class FakeBoolController extends FakeNotifier<bool> {
  FakeBoolController({this.initialValue = false});

  /// State returned by [build].
  final bool initialValue;

  @override
  bool build() => initialValue;

  /// Replaces the current state, rebuilding listeners.
  void setValue(bool value) => state = value;
}

/// Double for a `NotifierProvider<..., Object?>` whose state the test drives.
///
/// The provider starts at [initialValue]; [setValue] pushes a new value so the
/// widgets watching the provider rebuild.
class FakeObjectController extends FakeNotifier<Object?> {
  FakeObjectController({this.initialValue});

  /// State returned by [build].
  final Object? initialValue;

  @override
  Object? build() => initialValue;

  /// Replaces the current state, rebuilding listeners.
  void setValue(Object? value) => state = value;
}

/// Double for the account-entitlement provider.
///
/// Entitlement starts inactive; [setActive] flips it so gated UI rebuilds into
/// the paid or free state without a billing backend.
class FakeEntitlementController extends FakeNotifier<bool> {
  FakeEntitlementController({this.initialActive = false});

  /// State returned by [build].
  final bool initialActive;

  @override
  bool build() => initialActive;

  /// Replaces the current entitlement, rebuilding listeners.
  void setActive(bool value) => state = value;
}
