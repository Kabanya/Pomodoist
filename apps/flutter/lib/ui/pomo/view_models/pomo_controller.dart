import '../models/pomo_host.dart';
export '../models/pomo_host.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:pomodoist/data/repositories/pomo/pomo_preferences_repository.dart';
import 'package:pomodoist/domain/models/pomo/pomo_models.dart';
import 'package:pomodoist/domain/models/pomo/pomo_focus.dart';
import 'package:pomodoist/domain/models/pomo/pomo_reactions.dart';
import 'package:pomodoist/domain/models/tasks/local_completion_event.dart';

/// Owns visibility and finite reactions; no independent timer/session state.
class PomoController extends ChangeNotifier {
  PomoController(
    this.preferences,
    this.host, {
    PomoReactions? reactions,
    this.hostAvailable = true,
  }) : reactions = reactions ?? PomoReactions() {
    _reactionSubscription = this.reactions.changes.listen((_) {
      _notify();
      if (closing && !this.reactions.animated) _finishCloseMotion();
      if (!closing) _scheduleReconcile();
    });
    _preferencesSubscription = preferences.changes.listen((_) {
      this.reactions.setMotion(
        quiet: prefs.quiet,
        reduceMotion: prefs.reduceMotion || systemReduceMotion,
      );
      _notify();
      _scheduleReconcile();
    });
  }
  final PomoPreferencesRepository preferences;
  final PomoHost host;
  final PomoReactions reactions;
  late final StreamSubscription<void> _reactionSubscription;
  late final StreamSubscription<PomoPreferences> _preferencesSubscription;
  PomoPreferences get prefs => preferences.state;
  double? _draftScale;
  double _effectiveScale = 1;
  int _scaleRevision = 0;
  bool settingsOpen = false;
  Future<void>? _openingSettings;
  double get scale => _draftScale ?? prefs.scale;
  double get effectiveScale => visible ? _effectiveScale : scale;
  void appliedScale(double value) {
    if (_effectiveScale == value) return;
    _effectiveScale = value;
    _notify();
  }

  void previewScale(double value) {
    _scaleRevision++;
    _draftScale = PomoPreferences.normalizeScale(value);
    _notify();
    if (visible) unawaited(perform(() => host.setScale(scale)));
  }

  Future<void> changeScale(double value) {
    previewScale(value);
    return commitScale();
  }

  Future<void> commitScale() async {
    if (_draftScale == null) return;
    final value = scale, revision = _scaleRevision;
    await perform(() async {
      try {
        // Queue even a return to the saved value: an earlier write may be pending.
        await preferences.update((p) => p.copyWith(scale: value));
      } finally {
        if (revision == _scaleRevision) {
          _draftScale = null;
          if (visible) await host.setScale(scale);
        }
      }
    });
  }

  Future<void> openSettings() async {
    if (!visible || closing || settingsOpen) return;
    settingsOpen = true;
    _notify();
    final opening = perform(host.openSettings);
    _openingSettings = opening;
    await opening;
    _openingSettings = null;
    if (error != null) {
      settingsOpen = false;
      _notify();
    }
  }

  Future<void> closeSettings() async {
    if (!settingsOpen && _openingSettings == null) {
      await commitScale();
      return;
    }
    settingsOpen = false;
    _notify();
    await _openingSettings;
    await perform(host.closeSettings);
    await commitScale();
  }

  PomoFocus focus = const PomoFocus();
  bool visible = false, closing = false, menu = false, busy = false;
  bool systemReduceMotion = false,
      _explicit = false,
      _disposed = false,
      _ready = false;
  bool hostAvailable;

  Future<void> setHostAvailable(bool available) async {
    if (hostAvailable == available) return;
    hostAvailable = available;
    await perform(_reconcile);
  }

  Object? error;
  Timer? _reconcileTimer, _closingTimer;
  Completer<void>? _closingMotion;
  Future<void> _pending = Future.value();
  PomoEmotion get emotion => reactions.emotion ?? focus.background;
  bool get animated => visible && reactions.animated;
  bool get capsuleVisible => prefs.showTimer || error != null;
  Future<void> initialize() => perform(() async {
    await preferences.load();
    _ready = true;
    _effectiveScale = scale;
    await _reconcile();
  });
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> perform(Future<void> Function() action) async {
    try {
      await action();
      error = null;
    } on Object catch (e) {
      error = e;
    }
    try {
      if (visible) await host.setCapsuleVisible(capsuleVisible);
    } on Object catch (e) {
      error = e;
    }
    _notify();
  }

  void setSystemMotion(bool reduced) {
    systemReduceMotion = reduced;
    reactions.setMotion(
      quiet: prefs.quiet,
      reduceMotion: prefs.reduceMotion || reduced,
    );
  }

  void updateFocus(PomoFocus next) {
    if (focus.hasRun && !next.hasRun) _explicit = false;
    focus = next;
    _notify();
    _scheduleReconcile();
  }

  void completed(LocalCompletionEvent event) {
    if (!visible || closing) return;
    reactions.request(PomoEmotion.happy, eventId: event.operationId);
  }

  void _scheduleReconcile() {
    if (!_ready || _disposed) return;
    _reconcileTimer?.cancel();
    // Let commit notifications and the active-run stream settle together.
    _reconcileTimer = Timer(
      const Duration(milliseconds: 80),
      () => unawaited(
        _reconcile().catchError((Object e) {
          error = e;
          _notify();
        }),
      ),
    );
  }

  Future<void> _reconcile() {
    final next = _pending.then((_) async {
      if (_disposed || !_ready || closing) return;
      final wanted =
          hostAvailable &&
          prefs.shouldShow(hasRun: focus.hasRun, explicitShow: _explicit);
      if (wanted && !visible) {
        await host.show(prefs);
        if (_disposed ||
            !hostAvailable ||
            closing ||
            !prefs.shouldShow(hasRun: focus.hasRun, explicitShow: _explicit)) {
          await host.hide();
          return;
        }
        visible = true;
        menu = false;
        reactions.request(PomoEmotion.greeting);
        _notify();
      } else if (!wanted &&
          visible &&
          (!hostAvailable ||
              !prefs.enabled ||
              prefs.dismissed ||
              reactions.emotion != PomoEmotion.happy)) {
        await _hideNow();
      }
      if (visible) await host.setCapsuleVisible(capsuleVisible);
    });
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<void> restore() => perform(() async {
    _explicit = true;
    await preferences.update(
      (p) => p.copyWith(enabled: true, dismissed: false),
    );
    _ready = true;
    await _reconcile();
  });
  Future<void> toggleEnabled() async {
    if (busy || closing) return;
    busy = true;
    _notify();
    try {
      await setEnabled(!prefs.enabled);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> setEnabled(bool value) => value
      ? restore()
      : perform(() async {
          _explicit = false;
          await preferences.update((p) => p.copyWith(enabled: false));
          await _hideNow();
        });
  Future<void> updatePreferences(
    PomoPreferences Function(PomoPreferences) edit,
  ) => perform(() => preferences.update(edit));
  Future<void> resetPosition() => perform(() async {
    await preferences.update((p) => p.copyWith(resetPosition: true));
    if (visible) await host.resetPosition();
  });
  Future<void> hideManually() async {
    if (closing) return;
    closing = true;
    await closeSettings();
    menu = false;
    _explicit = false;
    reactions.request(PomoEmotion.sad);
    _notify();
    final delay = visible && reactions.animated
        ? const Duration(milliseconds: 900)
        : Duration.zero;
    _closingMotion = Completer<void>();
    _closingTimer = Timer(delay, _finishCloseMotion);
    await perform(() async {
      final save = preferences.update((p) => p.copyWith(dismissed: true));
      try {
        await Future.wait([
          save,
          _closingMotion!.future,
        ]).timeout(const Duration(milliseconds: 1200));
      } finally {
        _closingTimer?.cancel();
        _finishCloseMotion();
        _closingMotion = null;
        await _hideNow();
      }
    });
    closing = false;
    _notify();
  }

  void _finishCloseMotion() {
    final motion = _closingMotion;
    if (motion != null && !motion.isCompleted) motion.complete();
  }

  Future<void> _hideNow() async {
    _finishCloseMotion();
    try {
      await closeSettings();
      await host.hide();
    } finally {
      visible = false;
      menu = false;
      reactions.clear();
      _notify();
    }
  }

  Future<void> tap({bool react = true}) => perform(() async {
    if (closing || !visible) return;
    menu = !menu;
    if (react) reactions.request(PomoEmotion.surprised);
    _notify();
    await host.setMenu(menu);
  });
  Future<void> collapse() async {
    if (!menu) return;
    await perform(() async {
      menu = false;
      _notify();
      await host.setMenu(false);
    });
  }

  Future<void> command(Future<void> Function() action) async {
    if (busy || closing) return;
    busy = true;
    _notify();
    await perform(action);
    busy = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconcileTimer?.cancel();
    _closingTimer?.cancel();
    _finishCloseMotion();
    unawaited(_reactionSubscription.cancel());
    unawaited(_preferencesSubscription.cancel());
    reactions.dispose();
    unawaited(host.closeSettings().catchError((Object _) {}));
    unawaited(host.hide().catchError((Object _) {}));
    super.dispose();
  }
}

bool get pomoSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

// The composition root supplies one controller shared by every desktop view.
final pomoControllerProvider = ChangeNotifierProvider<PomoController>(
  (ref) => throw StateError('Pomo dependencies were not installed'),
);
final pomoFocusProvider = Provider<PomoFocus>(
  (ref) => throw StateError('Pomo dependencies were not installed'),
);
typedef PomoActions = ({
  Future<void> Function() openApp,
  Future<void> Function() toggleFocus,
  Future<void> Function() completeInterval,
  Future<void> Function() quickAdd,
});
final pomoActionsProvider = Provider<PomoActions>(
  (ref) => throw StateError('Pomo dependencies were not installed'),
);

Future<void> pomoToggleFocus(WidgetRef ref) =>
    ref.read(pomoActionsProvider).toggleFocus();
Future<void> pomoCompleteInterval(WidgetRef ref) =>
    ref.read(pomoActionsProvider).completeInterval();
