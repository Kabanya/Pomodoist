/// Runs a multi-repository local write as one database transaction.
///
/// The action must await every local write and rethrow inner failures so the
/// enclosing transaction rolls back; callers capture the outcome after it.
typedef RunLocalTransaction =
    Future<T> Function<T>(Future<T> Function() action);
