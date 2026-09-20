import 'dart:async';

import 'package:pomodoist/data/repositories/updates/update_repository.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/updates/update_contracts.dart';
import 'package:pomodoist/domain/models/updates/update_release.dart';

/// Preference adapter for the update channel and seen release tags. The
/// platform preference handle stays behind [PreferencesService].
class SharedUpdatePreferences implements UpdatePreferences {
  SharedUpdatePreferences(this._preferences);

  final PreferencesService _preferences;

  static const _channelKey = 'desktop.updater.channel';
  static const _seenKey = 'desktop.updater.seenTags';

  @override
  Future<SavedUpdatePreferences> load() async {
    final values = (await _preferences.read([
      _channelKey,
      _seenKey,
    ])).getOrThrow();
    final seen = values[_seenKey];
    return SavedUpdatePreferences(
      channel: values[_channelKey] == 'rc'
          ? UpdateChannel.rc
          : UpdateChannel.stable,
      seenTags: seen is List ? seen.whereType<String>().toSet() : const {},
    );
  }

  @override
  Future<void> setChannel(UpdateChannel channel) async {
    (await _preferences.write({_channelKey: channel.name})).getOrThrow();
  }

  @override
  Future<void> markSeen(Set<String> tags) async {
    (await _preferences.write({_seenKey: tags.toList()..sort()})).getOrThrow();
  }
}

/// Owns desktop update discovery, channel choice and download/install
/// progress. Popup visibility stays with the presentation owner.
class DesktopUpdateRepository implements UpdateRepository {
  DesktopUpdateRepository({
    required this.source,
    required this.installer,
    required this.preferences,
    required this.installedVersion,
    this.automaticChecks = true,
    this.officialUpdatesAllowed = false,
  });

  final UpdateSource source;
  final UpdateInstaller installer;
  final UpdatePreferences preferences;
  final Future<String> Function() installedVersion;
  @override
  final bool automaticChecks;
  final bool officialUpdatesAllowed;

  UpdateChannel _channel = UpdateChannel.stable;
  UpdatePhase _phase = UpdatePhase.idle;
  UpdateOffer? _offer;
  String? _error;
  double? _progress;
  DateTime? _lastChecked;
  final _seen = <String>{};
  bool _loaded = false;
  bool _disposed = false;
  bool _started = false;
  Future<void>? _loading;
  final _changes = StreamController<UpdateRepositoryState>.broadcast();

  bool get isDesktop => installer.target != null;
  bool get enabled =>
      officialUpdatesAllowed &&
      isDesktop &&
      installer.unavailableReason == null;
  bool get busy => const {
    UpdatePhase.checking,
    UpdatePhase.downloading,
    UpdatePhase.verifying,
    UpdatePhase.installing,
  }.contains(_phase);

  @override
  bool get started => _started;

  @override
  UpdateRepositoryState get state => UpdateRepositoryState(
    enabled: enabled,
    isDesktop: isDesktop,
    officialUpdatesAllowed: officialUpdatesAllowed,
    busy: busy,
    channel: _channel,
    phase: _phase,
    offer: _offer,
    error: _error,
    progress: _progress,
    lastChecked: _lastChecked,
    seenTags: Set.unmodifiable(_seen),
  );

  @override
  Stream<UpdateRepositoryState> watchState() {
    final controller = StreamController<UpdateRepositoryState>();
    controller.add(state);
    final subscription = _changes.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
    return controller.stream;
  }

  void _notify() {
    if (_disposed || _changes.isClosed) return;
    _changes.add(state);
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final pending = _loading;
    if (pending != null) {
      await pending;
      return;
    }
    final load = () async {
      final saved = await preferences.load();
      if (_disposed) return;
      _channel = saved.channel;
      _seen.addAll(saved.seenTags);
      _loaded = true;
    }();
    _loading = load;
    try {
      await load;
    } finally {
      _loading = null;
    }
  }

  @override
  Future<void> start() async {
    if (_started || _disposed || !isDesktop) return;
    _started = true;
    // Acknowledge a rendered application before preferences/network work. No
    // account or database contents are changed as part of this handshake.
    try {
      final warning = await installer.acknowledgeStartup();
      if (warning != null) {
        _error = warning;
        _phase = UpdatePhase.failed;
      }
    } catch (_) {
      /* Helper will roll back if startup cannot be acknowledged. */
    }
    if (!enabled || _disposed) return;
    try {
      await _ensureLoaded();
    } catch (_) {
      _error = 'Could not load update preferences. Try a manual check.';
      _phase = UpdatePhase.failed;
    }
    if (_disposed) return;
    _notify();
  }

  @override
  Future<UpdateCheckOutcome> check({bool manual = false}) async {
    if (!enabled || busy || _disposed) return UpdateCheckOutcome.skipped;
    _phase = UpdatePhase.checking;
    _lastChecked = DateTime.now();
    _error = null;
    _notify();
    var presented = false;
    try {
      await _ensureLoaded();
      if (_disposed) return UpdateCheckOutcome.skipped;
      final current = UpdateVersion.parse(await installedVersion());
      if (_disposed) return UpdateCheckOutcome.skipped;
      final next = await source.findUpdate(
        current: current,
        target: installer.target!,
        channel: _channel,
      );
      if (_disposed) return UpdateCheckOutcome.skipped;
      _offer = next;
      _lastChecked = DateTime.now();
      presented = next != null && (manual || !_seen.contains(next.tag));
      if (presented) {
        // Persist before display: dismissal, crashes and restarts cannot turn
        // the same automatic notification into a repeated interruption.
        final updated = {..._seen, next.tag};
        await preferences.markSeen(updated);
        if (_disposed) return UpdateCheckOutcome.skipped;
        _seen.add(next.tag);
      }
      _phase = next == null ? UpdatePhase.upToDate : UpdatePhase.available;
    } catch (failure) {
      if (_disposed) return UpdateCheckOutcome.skipped;
      _phase = UpdatePhase.failed;
      _error = failure.toString();
      if (!_disposed) _notify();
      return UpdateCheckOutcome.failed;
    }
    if (!_disposed) _notify();
    if (_offer == null) return UpdateCheckOutcome.upToDate;
    return presented
        ? UpdateCheckOutcome.newOffer
        : UpdateCheckOutcome.seenOffer;
  }

  @override
  Future<void> setChannel(UpdateChannel next) async {
    if (!enabled || busy || _disposed) return;
    _phase = UpdatePhase.checking;
    _notify();
    try {
      await _ensureLoaded();
      if (_disposed) return;
      await preferences.setChannel(next);
      if (_disposed) return;
      _channel = next;
      _offer = null;
      _error = null;
      _phase = UpdatePhase.idle;
      await check(manual: true);
    } catch (_) {
      if (_disposed) return;
      _phase = UpdatePhase.failed;
      _error = 'Could not save the update channel. Please try again.';
      _notify();
    }
  }

  @override
  Future<void> update() async {
    final selected = _offer;
    if (!enabled ||
        busy ||
        _disposed ||
        selected == null ||
        (_channel == UpdateChannel.stable && !selected.version.isStable)) {
      return;
    }
    _phase = UpdatePhase.downloading;
    _error = null;
    _progress = 0;
    _notify();
    try {
      await installer.install(selected, (stage, fraction) {
        if (_disposed) return;
        _phase = stage;
        _progress = fraction;
        _notify();
      });
    } catch (failure) {
      if (_disposed) return;
      _error = failure.toString();
      _phase = UpdatePhase.failed;
      _progress = null;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes.close());
    source.dispose();
    installer.dispose();
  }
}
