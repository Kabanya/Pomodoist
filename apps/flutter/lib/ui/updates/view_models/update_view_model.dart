import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/update_dependencies.dart';
import 'package:pomodoist/data/repositories/updates/update_repository.dart';
import 'package:pomodoist/domain/models/updates/update_contracts.dart';
import 'package:pomodoist/domain/models/updates/update_release.dart';

class UpdateState {
  const UpdateState({
    required this.enabled,
    required this.isDesktop,
    required this.officialUpdatesAllowed,
    required this.channel,
    required this.phase,
    required this.offer,
    required this.error,
    required this.progress,
    required this.popupVisible,
    required this.busy,
  });
  final bool enabled, isDesktop, officialUpdatesAllowed, popupVisible, busy;
  final UpdateChannel channel;
  final UpdatePhase phase;
  final UpdateOffer? offer;
  final String? error;
  final double? progress;
}

final updateViewModelProvider =
    NotifierProvider.autoDispose<UpdateViewModel, UpdateState>(
      UpdateViewModel.new,
    );

class UpdateViewModel extends Notifier<UpdateState> {
  late UpdateRepository _repository;
  StreamSubscription<UpdateRepositoryState>? _subscription;
  Timer? _startupTimer;
  Timer? _periodicTimer;
  bool _popupVisible = false;
  bool _timersStarted = false;

  UpdateState _snapshot() {
    final repository = _repository.state;
    return UpdateState(
      enabled: repository.enabled,
      isDesktop: repository.isDesktop,
      officialUpdatesAllowed: repository.officialUpdatesAllowed,
      channel: repository.channel,
      phase: repository.phase,
      offer: repository.offer,
      error: repository.error,
      progress: repository.progress,
      popupVisible: _popupVisible,
      busy: repository.busy,
    );
  }

  @override
  UpdateState build() {
    _repository = ref.watch(updateRepositoryProvider);
    _subscription = _repository.watchState().listen((_) => _emit());
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
      _startupTimer?.cancel();
      _periodicTimer?.cancel();
    });
    return _snapshot();
  }

  void _emit() {
    if (ref.mounted) state = _snapshot();
  }

  Future<void> start() async {
    await _repository.start();
    if (!ref.mounted || !_repository.automaticChecks || _timersStarted) {
      return;
    }
    _timersStarted = true;
    _startupTimer = Timer(
      const Duration(seconds: 10),
      () => unawaited(check()),
    );
    _periodicTimer = Timer.periodic(
      const Duration(hours: 6),
      (_) => unawaited(check()),
    );
  }

  void onResume() {
    final repository = _repository.state;
    if (!_repository.automaticChecks ||
        !_repository.started ||
        repository.busy) {
      return;
    }
    final lastChecked = repository.lastChecked;
    if (lastChecked == null ||
        DateTime.now().difference(lastChecked) >= const Duration(hours: 1)) {
      unawaited(check());
    }
  }

  Future<void> check({bool manual = false}) async {
    final outcome = await _repository.check(manual: manual);
    if (!ref.mounted) return;
    switch (outcome) {
      case UpdateCheckOutcome.skipped:
        return;
      case UpdateCheckOutcome.failed:
        if (manual) _setPopup(true);
        return;
      case UpdateCheckOutcome.upToDate:
        _setPopup(false);
        return;
      case UpdateCheckOutcome.newOffer:
        _setPopup(true);
        return;
      case UpdateCheckOutcome.seenOffer:
        return;
    }
  }

  Future<void> setChannel(UpdateChannel value) async {
    final before = _repository.state;
    if (!before.enabled || before.busy) return;
    await _repository.setChannel(value);
    if (!ref.mounted) return;
    final repository = _repository.state;
    if (repository.channel != value) {
      _setPopup(false);
      return;
    }
    _setPopup(
      repository.phase == UpdatePhase.failed || repository.offer != null,
    );
  }

  void dismiss() => _setPopup(false);

  Future<void> update() => _repository.update();

  void _setPopup(bool value) {
    if (_popupVisible == value) return;
    _popupVisible = value;
    _emit();
  }
}
