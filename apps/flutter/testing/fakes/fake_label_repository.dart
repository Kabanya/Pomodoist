import 'package:pomodoist/data/repositories/labels/label_repository.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/utils/result.dart';

import 'strict_fake.dart';

/// In-memory [LabelRepository] double.
///
/// Succeeding calls answer from the mutable fields below, every call is
/// recorded in its `<method>Calls` list, and a call whose `<method>Error`
/// field is non-null fails with that error instead of succeeding.
class FakeLabelRepository extends StrictFake implements LabelRepository {
  /// Labels emitted by [watchLabels].
  List<LabelItem> labels = const [];

  /// Label [findByName] succeeds with.
  LabelItem? labelByName;

  /// Id [createLabel] succeeds with.
  String createdLabelId = 'label-1';

  Object? findByNameError;
  Object? createLabelError;
  Object? updateLabelIconError;
  Object? deleteLabelError;

  final watchLabelsCalls = <void>[];
  final findByNameCalls = <String>[];
  final createLabelCalls = <({String name, String? icon})>[];
  final updateLabelIconCalls = <({String id, String icon})>[];
  final deleteLabelCalls = <String>[];

  @override
  Stream<List<LabelItem>> watchLabels() {
    watchLabelsCalls.add(null);
    return Stream.value(labels);
  }

  @override
  Future<Result<LabelItem?>> findByName(String name) async {
    findByNameCalls.add(name);
    final error = findByNameError;
    if (error != null) return Result.error(error, StackTrace.current);
    return Result.ok(labelByName);
  }

  @override
  Future<Result<String>> createLabel(String name, {String? icon}) async {
    createLabelCalls.add((name: name, icon: icon));
    final error = createLabelError;
    if (error != null) return Result.error(error, StackTrace.current);
    return Result.ok(createdLabelId);
  }

  @override
  Future<Result<void>> updateLabelIcon(String id, String icon) async {
    updateLabelIconCalls.add((id: id, icon: icon));
    final error = updateLabelIconError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> deleteLabel(String id) async {
    deleteLabelCalls.add(id);
    final error = deleteLabelError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }
}
