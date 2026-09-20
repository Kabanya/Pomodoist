import 'dart:async';

import 'package:pomodoist/data/repositories/planning/quick_add_hint_repository.dart';
import 'package:pomodoist/data/services/planning/quick_add_hint.dart';
import 'package:pomodoist/domain/models/planning/quick_add_hint.dart';

int firstQuickAddHintRefreshAt({required bool hasActiveEntitlement}) {
  return 1;
}

int nextQuickAddHintRefreshAfter(
  int createdTaskCount, {
  bool hasActiveEntitlement = true,
}) {
  if (!hasActiveEntitlement && createdTaskCount >= 1000) {
    return ((createdTaskCount ~/ 500) + 1) * 500;
  }
  if (createdTaskCount < 1) {
    return 1;
  }
  if (createdTaskCount < 10) {
    return 10;
  }
  if (createdTaskCount < 25) {
    return 25;
  }
  if (createdTaskCount < 50) {
    return 50;
  }
  return ((createdTaskCount ~/ 50) + 1) * 50;
}

class StoredQuickAddHintRepository implements QuickAddHintRepository {
  StoredQuickAddHintRepository({
    required QuickAddHintHistory history,
    required QuickAddHintStore store,
    required QuickAddHintGenerator generator,
    required String Function() locale,
    bool Function()? hasActiveEntitlement,
  }) : _history = history,
       _store = store,
       _generator = generator,
       _locale = locale,
       _hasActiveEntitlement = hasActiveEntitlement ?? _alwaysPaid;

  final QuickAddHintHistory _history;
  final QuickAddHintStore _store;
  final QuickAddHintGenerator _generator;
  final String Function() _locale;
  final bool Function() _hasActiveEntitlement;
  final _states = StreamController<QuickAddHintState>.broadcast(sync: true);
  bool _disposed = false;
  Future<void>? _initialization;
  var _refreshing = false;

  QuickAddHintState _state = QuickAddHintState(
    createdTaskCount: 0,
    nextRefreshAt: 1,
    retryPending: false,
  );

  @override
  QuickAddHintState get state => _state;

  @override
  Stream<QuickAddHintState> watch() => _states.stream;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _states.close();
  }

  @override
  Future<void> initialize() {
    if (_disposed) return Future.value();
    return _initialization ??= _initialize();
  }

  @override
  Future<void> recordUserTaskCreated() async {
    await initialize();
    if (_disposed) return;
    await _alignScheduleToEntitlement();
    if (_disposed) return;
    _state = _state.copyWith(createdTaskCount: _state.createdTaskCount + 1);
    if (!_state.retryPending &&
        _state.createdTaskCount >= _state.nextRefreshAt) {
      _state = _state.copyWith(retryPending: true);
    }
    await _writeState();
    if (_state.retryPending) {
      await _refresh();
    }
  }

  Future<void> _initialize() async {
    try {
      final stored = await _store.read();
      if (_disposed) return;
      if (stored != null) {
        _state = stored;
        _states.add(_state);
      } else {
        final count = await _history.countExistingUserTasks();
        if (_disposed) return;
        final hasActiveEntitlement = _hasActiveEntitlement();
        _state = QuickAddHintState(
          createdTaskCount: count,
          nextRefreshAt: nextQuickAddHintRefreshAfter(
            count,
            hasActiveEntitlement: hasActiveEntitlement,
          ),
          retryPending:
              count >=
              firstQuickAddHintRefreshAt(
                hasActiveEntitlement: hasActiveEntitlement,
              ),
        );
        await _writeState();
      }
      if (_disposed) return;
      await _alignScheduleToEntitlement();
      if (_disposed) return;
      if (!_state.retryPending &&
          _state.createdTaskCount >= _state.nextRefreshAt) {
        _state = _state.copyWith(retryPending: true);
        await _writeState();
      }
      if (_state.retryPending) {
        await _refresh();
      }
    } catch (_) {
      // A hint is optional and must never affect task creation or app startup.
    }
  }

  Future<void> _refresh() async {
    if (_disposed || _refreshing || !_state.retryPending) {
      return;
    }
    _refreshing = true;
    final locale = _locale();
    try {
      final titles = await _history.recentTaskTitles(
        limit: quickAddHintHistoryLimit,
      );
      if (_disposed) return;
      final hint = normalizeQuickAddHint(
        await _generator.generate(recentTaskTitles: titles, locale: locale),
      );
      if (_disposed) return;
      if (hint == null) {
        throw const QuickAddHintException('DeepSeek returned an invalid hint.');
      }
      _state = _state.copyWith(
        starterConsumed: true,
        recentHints: retainRecentQuickAddHints([
          ..._state.recentHints,
          QuickAddHint(text: hint, locale: locale),
        ]),
        nextRefreshAt: nextQuickAddHintRefreshAfter(
          _state.createdTaskCount,
          hasActiveEntitlement: _hasActiveEntitlement(),
        ),
        retryPending: false,
      );
    } catch (_) {
      // Keep the previous hint and retry the same threshold on the next launch.
    } finally {
      _refreshing = false;
      await _writeState();
    }
  }

  Future<void> _writeState() async {
    if (_disposed) return;
    await _store.write(_state);
    if (!_disposed) _states.add(_state);
  }

  Future<void> _alignScheduleToEntitlement() async {
    if (_state.retryPending) {
      return;
    }
    final nextRefreshAt = nextQuickAddHintRefreshAfter(
      _state.createdTaskCount,
      hasActiveEntitlement: _hasActiveEntitlement(),
    );
    if (_state.nextRefreshAt == nextRefreshAt) {
      return;
    }
    _state = _state.copyWith(nextRefreshAt: nextRefreshAt);
    await _writeState();
  }
}

bool _alwaysPaid() => true;
