import 'dart:async';
import 'dart:math';

import 'package:app_account/app_account.dart';
import 'package:flutter/widgets.dart';

import '../db/app_database.dart';
import 'account_sync_engine.dart';
import 'sync_queue_repository.dart';

class AccountSyncLifecycle with WidgetsBindingObserver {
  static const defaultPollInterval = Duration(minutes: 1);
  static const defaultRetryDelays = <Duration>[
    Duration(seconds: 30),
    Duration(minutes: 1),
  ];
  static final _retryRandom = Random();

  static Duration boundedRetryDelay(Duration base, {double? sample}) {
    final jitter = (sample ?? _retryRandom.nextDouble()).clamp(0.0, 1.0);
    return Duration(
      microseconds: (base.inMicroseconds * (0.9 + jitter * 0.1)).round(),
    );
  }

  AccountSyncLifecycle({
    required AccountClient account,
    required AccountSyncEngine engine,
    required SyncQueueRepository syncQueueRepository,
    Future<void> Function()? onSynced,
    Duration? pollInterval,
    Duration? queueDebounce,
    Duration? hintResubscribeDelay,
    List<Duration>? retryDelays,
  }) : _syncNowCallback = engine.syncNow,
       _deviceId = engine.deviceId,
       _syncHints = (() => account.syncHints(appId: AccountAppId.pomodoist)),
       _syncQueueRepository = syncQueueRepository,
       _onSynced = onSynced,
       _pollInterval = pollInterval ?? defaultPollInterval,
       _queueDebounce = queueDebounce ?? const Duration(milliseconds: 800),
       _hintResubscribeDelay =
           hintResubscribeDelay ?? const Duration(seconds: 5),
       _retryDelays = retryDelays ?? defaultRetryDelays;

  AccountSyncLifecycle.forTesting({
    required Future<void> Function() syncNow,
    required Future<String> Function() deviceId,
    required Stream<AccountSyncHint> Function() syncHints,
    required SyncQueueRepository syncQueueRepository,
    Future<void> Function()? onSynced,
    Duration pollInterval = defaultPollInterval,
    Duration queueDebounce = const Duration(milliseconds: 800),
    Duration hintResubscribeDelay = const Duration(seconds: 5),
    List<Duration> retryDelays = defaultRetryDelays,
  }) : _syncNowCallback = syncNow,
       _deviceId = deviceId,
       _syncHints = syncHints,
       _syncQueueRepository = syncQueueRepository,
       _onSynced = onSynced,
       _pollInterval = pollInterval,
       _queueDebounce = queueDebounce,
       _hintResubscribeDelay = hintResubscribeDelay,
       _retryDelays = retryDelays;

  final Future<void> Function() _syncNowCallback;
  final Future<String> Function() _deviceId;
  final Stream<AccountSyncHint> Function() _syncHints;
  final SyncQueueRepository _syncQueueRepository;
  final Future<void> Function()? _onSynced;
  final Duration _pollInterval;
  final Duration _queueDebounce;
  final Duration _hintResubscribeDelay;
  final List<Duration> _retryDelays;

  Timer? _timer;
  Timer? _debounce;
  Timer? _retryTimer;
  Timer? _hintResubscribeTimer;
  StreamSubscription<List<SyncCommandRow>>? _queueSubscription;
  StreamSubscription<AccountSyncHint>? _hintSubscription;
  bool _syncing = false;
  bool _syncAgain = false;
  bool _disposed = false;
  int _retryAttempt = 0;

  void start() {
    if (_disposed) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _timer ??= Timer.periodic(_pollInterval, (_) => unawaited(_syncNow()));
    _queueSubscription ??= _syncQueueRepository.watchPending().listen((
      commands,
    ) {
      if (commands.isEmpty) {
        return;
      }
      _scheduleSync();
    });
    _startHintSubscription();
    unawaited(_syncNow());
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _debounce?.cancel();
    _retryTimer?.cancel();
    _hintResubscribeTimer?.cancel();
    unawaited(_queueSubscription?.cancel());
    unawaited(_hintSubscription?.cancel());
    _timer = null;
    _debounce = null;
    _retryTimer = null;
    _hintResubscribeTimer = null;
    _queueSubscription = null;
    _hintSubscription = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncNow());
    }
  }

  void _scheduleSync([Duration? delay]) {
    if (_disposed) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(delay ?? _queueDebounce, () => unawaited(_syncNow()));
  }

  void _scheduleHintResubscribe() {
    if (_disposed) {
      return;
    }
    _hintResubscribeTimer?.cancel();
    _hintResubscribeTimer = Timer(_hintResubscribeDelay, () {
      unawaited(_hintSubscription?.cancel());
      _hintSubscription = null;
      _startHintSubscription(syncAfterSubscribe: true);
    });
  }

  void _startHintSubscription({bool syncAfterSubscribe = false}) {
    if (_disposed) {
      return;
    }
    try {
      _hintSubscription = _syncHints().listen(
        (hint) => unawaited(_handleHint(hint)),
        onError: (_) => _scheduleHintResubscribe(),
        onDone: _scheduleHintResubscribe,
        cancelOnError: true,
      );
      if (syncAfterSubscribe) {
        unawaited(_syncNow());
      }
    } catch (_) {
      _scheduleHintResubscribe();
    }
  }

  Future<void> _handleHint(AccountSyncHint hint) async {
    if (hint.deviceId == await _deviceId()) {
      return;
    }
    await _syncNow();
  }

  Future<void> _syncNow() async {
    if (_disposed) {
      return;
    }
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    var synced = false;
    try {
      await _syncNowCallback();
      synced = true;
      _retryAttempt = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
    } catch (_) {
      _scheduleRetry();
    } finally {
      _syncing = false;
    }
    if (_syncAgain) {
      _syncAgain = false;
      _scheduleSync(Duration.zero);
    }
    if (synced) {
      try {
        await _onSynced?.call();
      } catch (_) {
        // Account sync succeeded; integrations retry through their own flows.
      }
    }
  }

  void _scheduleRetry() {
    if (_disposed || _retryDelays.isEmpty) {
      return;
    }
    final index = _retryAttempt >= _retryDelays.length
        ? _retryDelays.length - 1
        : _retryAttempt;
    _retryAttempt += 1;
    _retryTimer?.cancel();
    _retryTimer = Timer(
      boundedRetryDelay(_retryDelays[index]),
      () => unawaited(_syncNow()),
    );
  }
}
