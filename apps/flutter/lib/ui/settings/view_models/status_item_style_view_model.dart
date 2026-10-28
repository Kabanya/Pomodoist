import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/status_item_style_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/status_item_style_repository.dart';
import 'package:pomodoist/domain/models/settings/status_item_style.dart';

final statusItemStyleProvider =
    NotifierProvider.autoDispose<
      StatusItemStyleViewModel,
      StatusItemStyleState
    >(StatusItemStyleViewModel.new);

class StatusItemStyleState {
  const StatusItemStyleState({this.style, this.isBusy = false, this.error});
  final StatusItemStyle? style;
  final bool isBusy;
  final Object? error;
}

class StatusItemStyleViewModel extends Notifier<StatusItemStyleState> {
  late StatusItemStyleRepository _repository;
  Future<StatusItemStyle> Function()? _retryOperation;
  int _revision = 0;

  @override
  StatusItemStyleState build() {
    _repository = ref.watch(statusItemStyleRepositoryProvider);
    final subscription = _repository.changes.listen((style) {
      _revision++;
      _retryOperation = null;
      state = StatusItemStyleState(style: style, isBusy: state.isBusy);
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    unawaited(
      Future<void>.microtask(() async {
        if (ref.mounted) await refresh();
      }),
    );
    return const StatusItemStyleState();
  }

  Future<void> refresh() => _apply(_repository.read);

  Future<void> retry() => _apply(_retryOperation ?? _repository.read);

  Future<void> select(StatusItemStyle style) async {
    if (state.style == null || state.style == style) return;
    await _apply(() => _repository.select(style));
  }

  Future<void> _apply(Future<StatusItemStyle> Function() operation) async {
    if (state.isBusy) return;
    _retryOperation = null;
    final revision = _revision;
    state = StatusItemStyleState(style: state.style, isBusy: true);
    try {
      final style = await operation();
      if (ref.mounted) {
        state = StatusItemStyleState(
          style: revision == _revision ? style : state.style,
        );
      }
    } catch (error) {
      if (ref.mounted) {
        _retryOperation = revision == _revision ? operation : null;
        state = StatusItemStyleState(
          style: state.style,
          error: revision == _revision ? error : null,
        );
      }
    }
  }
}
