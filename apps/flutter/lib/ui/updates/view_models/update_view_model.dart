import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/update_dependencies.dart';
import 'package:pomodoist/data/repositories/updates/update_controller.dart';
import 'package:pomodoist/domain/models/updates/update_contracts.dart';
import 'package:pomodoist/domain/models/updates/update_release.dart';

enum UpdateSurface { host, popup, settings }

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

final updateViewModelProvider = NotifierProvider.autoDispose
    .family<UpdateViewModel, UpdateState, UpdateSurface>(UpdateViewModel.new);

class UpdateViewModel extends Notifier<UpdateState> {
  UpdateViewModel(this.surface);
  final UpdateSurface surface;
  late DesktopUpdateController _repository;
  UpdateState _snapshot() => UpdateState(
    enabled: _repository.enabled,
    isDesktop: _repository.isDesktop,
    officialUpdatesAllowed: _repository.officialUpdatesAllowed,
    channel: _repository.channel,
    phase: _repository.phase,
    offer: _repository.offer,
    error: _repository.error,
    progress: _repository.progress,
    popupVisible: _repository.popupVisible,
    busy: _repository.busy,
  );
  @override
  UpdateState build() {
    final repository = ref.watch(desktopUpdateControllerProvider);
    _repository = repository;
    void changed() {
      if (ref.mounted) state = _snapshot();
    }

    repository.addListener(changed);
    ref.onDispose(() => repository.removeListener(changed));
    return _snapshot();
  }

  Future<void> start() => _repository.start();
  void onResume() => _repository.onResume();
  void dismiss() => _repository.dismiss();
  Future<void> update() => _repository.update();
  Future<void> check({bool manual = false}) =>
      _repository.check(manual: manual);
  Future<void> setChannel(UpdateChannel value) => _repository.setChannel(value);
}
