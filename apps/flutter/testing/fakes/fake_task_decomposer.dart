import 'dart:async';

import 'package:pomodoist/data/repositories/planning/task_decomposition_repository.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';

import 'strict_fake.dart';

/// Test double for [TaskDecomposer] that records every call.
///
/// By default [decompose] resolves immediately with [drafts]. Set [hold] to
/// keep calls pending and release them with [complete] or [fail], and set
/// [decomposeError] to fail a call instead of resolving it.
class FakeTaskDecomposer extends StrictFake implements TaskDecomposer {
  /// Drafts returned by [decompose] when [hold] is false and no
  /// [decomposeError] is set.
  List<DecomposedTaskDraft> drafts = const [];

  /// When non-null, [decompose] throws this instead of returning [drafts].
  Object? decomposeError;

  /// When true, [decompose] stays pending until [complete] or [fail] releases
  /// the call.
  bool hold = false;

  final transcripts = <String>[];
  final locales = <String>[];
  final smartModes = <bool>[];
  final _pending = <Completer<List<DecomposedTaskDraft>>>[];

  @override
  Future<List<DecomposedTaskDraft>> decompose(
    String transcript, {
    required DateTime now,
    required String locale,
    bool smartMode = false,
  }) async {
    transcripts.add(transcript);
    locales.add(locale);
    smartModes.add(smartMode);
    final error = decomposeError;
    if (error != null) {
      throw error;
    }
    if (!hold) {
      return drafts;
    }
    final completer = Completer<List<DecomposedTaskDraft>>();
    _pending.add(completer);
    return completer.future;
  }

  /// Completes the [index]-th pending call with [drafts], counting from the
  /// first call still waiting on [hold].
  void complete(List<DecomposedTaskDraft> drafts, {int index = 0}) =>
      _pending[index].complete(drafts);

  /// Fails the [index]-th pending call with [error].
  void fail(Object error, {int index = 0}) =>
      _pending[index].completeError(error);
}
