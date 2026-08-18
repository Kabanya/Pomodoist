import 'dart:async';

import 'native_link_coordinator_core.dart';

final class NativeAccountStartup<T> {
  NativeAccountStartup._({
    required NativeLinkCoordinator links,
    required Future<T> Function() initializeAccount,
  }) : _links = links,
       _initializeAccount = initializeAccount {
    initialAttempt = _beginAttempt();
  }

  final NativeLinkCoordinator _links;
  final Future<T> Function() _initializeAccount;
  late final Future<T> initialAttempt;
  bool _initialAttemptClaimed = false;

  Future<T> initializeAccount() {
    if (!_initialAttemptClaimed) {
      _initialAttemptClaimed = true;
      return initialAttempt;
    }
    return _beginAttempt();
  }

  Future<T> _beginAttempt() {
    final attempt = Future<T>.sync(_initializeAccount);
    unawaited(
      attempt.then<void>(
        (_) => _startLinksSafely(),
        onError: (Object _, StackTrace _) {},
      ),
    );
    return attempt;
  }

  Future<void> _startLinksSafely() async {
    try {
      await _links.start();
    } on Object {
      // Link startup must not replace the account bootstrap result.
    }
  }
}

Future<NativeAccountStartup<T>> prepareNativeAccountStartup<T>({
  required NativeLinkCoordinator links,
  required Future<T> Function() initializeAccount,
}) async {
  await links.prepare();
  return NativeAccountStartup._(
    links: links,
    initializeAccount: initializeAccount,
  );
}
