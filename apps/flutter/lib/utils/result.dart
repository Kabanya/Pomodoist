import 'dart:async';

/// An operation's value or its original failure. Streams use stream errors.
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Success<T>;
  const factory Result.error(Object error, StackTrace stackTrace) = Failure<T>;

  static Future<Result<T>> capture<T>(FutureOr<T> Function() action) async {
    try {
      return Success(await action());
    } catch (error, stackTrace) {
      return Failure(error, stackTrace);
    }
  }

  /// Use inside an enclosing transaction or an AsyncValue.guard boundary.
  /// Rethrowing inside a transaction is essential: returning Failure commits it.
  T getOrThrow() => switch (this) {
    Success<T>(:final value) => value,
    Failure<T>(:final error, :final stackTrace) => Error.throwWithStackTrace(
      error,
      stackTrace,
    ),
  };
}

final class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

final class Failure<T> extends Result<T> {
  const Failure(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}
