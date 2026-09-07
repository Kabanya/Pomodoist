import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_contracts.dart';
import 'update_release.dart';

class SharedUpdatePreferences implements UpdatePreferences {
  final _preferences = SharedPreferencesAsync();
  static const _channelKey = 'desktop.updater.channel';
  static const _seenKey = 'desktop.updater.seenTags';

  @override
  Future<SavedUpdatePreferences> load() async => SavedUpdatePreferences(
    channel: await _preferences.getString(_channelKey) == 'rc'
        ? UpdateChannel.rc : UpdateChannel.stable,
    seenTags: (await _preferences.getStringList(_seenKey) ?? const <String>[]).toSet(),
  );
  @override
  Future<void> setChannel(UpdateChannel channel) =>
      _preferences.setString(_channelKey, channel.name);
  @override
  Future<void> markSeen(Set<String> tags) =>
      _preferences.setStringList(_seenKey, tags.toList()..sort());
}

class DesktopUpdateController extends ChangeNotifier {
  DesktopUpdateController({required this.source, required this.installer,
    required this.preferences, required this.installedVersion,
    this.automaticChecks = true});

  final UpdateSource source;
  final UpdateInstaller installer;
  final UpdatePreferences preferences;
  final Future<String> Function() installedVersion;
  final bool automaticChecks;
  UpdateChannel channel = UpdateChannel.stable;
  UpdatePhase phase = UpdatePhase.idle;
  UpdateOffer? offer;
  String? error;
  double? progress;
  bool popupVisible = false;
  DateTime? lastChecked;
  final _seen = <String>{};
  bool _loaded = false;
  bool _disposed = false;
  bool _started = false;
  Future<void>? _loading;
  Timer? _startupTimer;
  Timer? _periodicTimer;

  bool get isDesktop => installer.target != null;
  bool get enabled => isDesktop && installer.unavailableReason == null;
  bool get busy => const {UpdatePhase.checking, UpdatePhase.downloading,
    UpdatePhase.verifying, UpdatePhase.installing}.contains(phase);

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final pending = _loading;
    if (pending != null) { await pending; return; }
    final load = () async {
      final saved = await preferences.load();
      if (_disposed) return;
      channel = saved.channel;
      _seen.addAll(saved.seenTags);
      _loaded = true;
    }();
    _loading = load;
    try { await load; } finally { _loading = null; }
  }

  Future<void> start() async {
    if (_started || _disposed || !isDesktop) return;
    _started = true;
    // Acknowledge a rendered application before preferences/network work. No
    // account or database contents are changed as part of this handshake.
    try {
      final warning = await installer.acknowledgeStartup();
      if (warning != null) { error = warning; phase = UpdatePhase.failed; }
    } catch (_) { /* Helper will roll back if startup cannot be acknowledged. */ }
    if (!enabled || _disposed) return;
    try {
      await _ensureLoaded();
    } catch (_) {
      error = 'Could not load update preferences. Try a manual check.';
      phase = UpdatePhase.failed;
    }
    if (_disposed) return;
    notifyListeners();
    if (automaticChecks) {
      _startupTimer = Timer(const Duration(seconds: 10), () => unawaited(check()));
      _periodicTimer = Timer.periodic(const Duration(hours: 6), (_) => unawaited(check()));
    }
  }

  void onResume() {
    if (!automaticChecks || !_started || _disposed) return;
    if (lastChecked == null || DateTime.now().difference(lastChecked!) >= const Duration(hours: 1)) {
      unawaited(check());
    }
  }

  Future<void> check({bool manual = false}) async {
    if (!enabled || busy || _disposed) return;
    phase = UpdatePhase.checking;
    lastChecked = DateTime.now();
    error = null;
    notifyListeners();
    try {
      await _ensureLoaded();
      if (_disposed) return;
      final current = UpdateVersion.parse(await installedVersion());
      if (_disposed) return;
      final next = await source.findUpdate(current: current,
        target: installer.target!, channel: channel);
      if (_disposed) return;
      offer = next;
      lastChecked = DateTime.now();
      if (next != null && (manual || !_seen.contains(next.tag))) {
        // Persist before display: dismissal, crashes and restarts cannot turn
        // the same automatic notification into a repeated interruption.
        final updated = {..._seen, next.tag};
        await preferences.markSeen(updated);
        if (_disposed) return;
        _seen.add(next.tag);
        popupVisible = true;
      } else if (next == null) {
        popupVisible = false;
      }
      phase = next == null ? UpdatePhase.upToDate : UpdatePhase.available;
    } catch (failure) {
      if (_disposed) return;
      phase = UpdatePhase.failed;
      error = failure.toString();
      // Automatic network failures stay in Settings, not intrusive popups.
      if (manual) popupVisible = true;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setChannel(UpdateChannel next) async {
    if (!enabled || busy || _disposed) return;
    phase = UpdatePhase.checking;
    notifyListeners();
    try {
      await _ensureLoaded();
      if (_disposed) return;
      await preferences.setChannel(next);
      if (_disposed) return;
      channel = next;
      offer = null;
      popupVisible = false;
      error = null;
      phase = UpdatePhase.idle;
      await check(manual: true);
    } catch (_) {
      if (_disposed) return;
      phase = UpdatePhase.failed;
      error = 'Could not save the update channel. Please try again.';
      notifyListeners();
    }
  }

  void dismiss() {
    if (_disposed) return;
    popupVisible = false;
    notifyListeners();
  }

  Future<void> update() async {
    final selected = offer;
    if (!enabled || busy || _disposed || selected == null ||
        (channel == UpdateChannel.stable && !selected.version.isStable)) return;
    phase = UpdatePhase.downloading;
    error = null;
    progress = 0;
    notifyListeners();
    try {
      await installer.install(selected, (stage, fraction) {
        if (_disposed) return;
        phase = stage;
        progress = fraction;
        notifyListeners();
      });
    } catch (failure) {
      if (_disposed) return;
      error = failure.toString();
      phase = UpdatePhase.failed;
      progress = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _startupTimer?.cancel();
    _periodicTimer?.cancel();
    source.dispose();
    installer.dispose();
    super.dispose();
  }
}
