import 'dart:async';
import 'dart:convert';

import 'package:pomodoist/data/repositories/platform/global_quick_add_repository.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/data/services/platform/global_quick_add_service.dart';
import 'package:pomodoist/data/services/platform/global_shortcut_codec.dart';

const globalQuickAddEnabledPreferenceKey = 'quick_add.global.enabled';
const globalQuickAddBindingPreferenceKey = 'quick_add.global.binding';

class LocalGlobalQuickAddRepository implements GlobalQuickAddRepository {
  LocalGlobalQuickAddRepository(this._platform, this._preferences)
    : _state = GlobalQuickAddState(
        enabled: true,
        binding: _platform.defaultBinding,
      ) {
    ready = _loadState();
  }

  final GlobalQuickAddService _platform;
  final PreferencesService _preferences;
  final _changes = StreamController<GlobalQuickAddState>.broadcast();
  GlobalQuickAddState _state;
  bool _disposed = false;
  @override
  GlobalQuickAddState get state => _state;
  @override
  late final Future<void> ready;

  @override
  Stream<GlobalQuickAddState> watchState() {
    final controller = StreamController<GlobalQuickAddState>();
    controller.add(state);
    final subscription = _changes.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
    return controller.stream;
  }

  void _publish(GlobalQuickAddState value) {
    if (_disposed) return;
    _state = value;
    _changes.add(value);
  }

  Future<void> _loadState() async {
    try {
      final values = (await _preferences.read([
        globalQuickAddEnabledPreferenceKey,
        globalQuickAddBindingPreferenceKey,
      ])).getOrThrow();
      if (_disposed) return;
      await _platform.initialize();
      if (_disposed) return;
      final enabled =
          values[globalQuickAddEnabledPreferenceKey] as bool? ?? true;
      _publish(state.copyWith(enabled: enabled));
      if (!_platform.supported) return;
      final rawBinding = values[globalQuickAddBindingPreferenceKey] as String?;
      final binding = await _platform.restore(
        enabled: enabled,
        savedBinding: rawBinding == null
            ? null
            : decodeGlobalShortcut(jsonDecode(rawBinding)),
      );
      _publish(state.copyWith(binding: binding, clearRegistrationError: true));
    } catch (error) {
      _publish(state.copyWith(registrationError: error));
    }
  }

  @override
  Future<GlobalQuickAddBinding> captureShortcut() =>
      _platform.captureShortcut();
  @override
  Future<void> cancelCapture() => _platform.cancelCapture();

  @override
  Future<void> setShortcut(GlobalQuickAddBinding binding) async {
    await ready;
    if (_disposed) return;
    final previous = state;
    var registered = false;
    try {
      if (previous.enabled) {
        try {
          await _platform.register(binding);
          registered = true;
        } catch (_) {
          try {
            await _platform.restoreRegistration(previous.binding);
          } catch (_) {
            // Keep the candidate registration error.
          }
          rethrow;
        }
      }
      (await _preferences.write({
        globalQuickAddBindingPreferenceKey: jsonEncode(binding.toJson()),
      })).getOrThrow();
      _publish(state.copyWith(binding: binding, clearRegistrationError: true));
    } catch (error) {
      if (registered) {
        try {
          await _platform.register(previous.binding);
        } catch (_) {
          // Report the original failure even if the native host is unavailable.
        }
      }
      _publish(state.copyWith(registrationError: error));
      rethrow;
    }
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    await ready;
    if (_disposed || state.enabled == enabled) return;
    final previous = state;
    var applied = false;
    try {
      await _platform.setEnabled(enabled, previous.binding);
      applied = true;
      (await _preferences.write({
        globalQuickAddEnabledPreferenceKey: enabled,
      })).getOrThrow();
      if (!enabled && !_disposed) await _platform.closeWindow();
      _publish(state.copyWith(enabled: enabled, clearRegistrationError: true));
    } catch (error) {
      if (applied) {
        try {
          await _platform.setEnabled(previous.enabled, previous.binding);
        } catch (_) {
          // Keep the original write error visible to the settings ViewModel.
        }
      }
      _publish(state.copyWith(registrationError: error));
      rethrow;
    }
  }

  void dispose() {
    _disposed = true;
    unawaited(_changes.close());
  }
}
