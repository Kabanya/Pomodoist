import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/sync/sync_queue_repository.dart';
import 'google_calendar_repository.dart';
import 'google_calendar_sync_controller.dart';

class GoogleCalendarSyncLifecycle with WidgetsBindingObserver {
  GoogleCalendarSyncLifecycle({
    required CalendarIntegrationRepository integrationRepository,
    required SyncQueueRepository syncQueueRepository,
    required GoogleCalendarSyncController syncController,
  }) : _integrationRepository = integrationRepository,
       _syncQueueRepository = syncQueueRepository,
       _syncController = syncController;

  final CalendarIntegrationRepository _integrationRepository;
  final SyncQueueRepository _syncQueueRepository;
  final GoogleCalendarSyncController _syncController;
  Timer? _timer;
  Timer? _localChangeDebounce;
  StreamSubscription<List<SyncCommandRow>>? _syncQueueSubscription;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _timer ??= Timer.periodic(
      const Duration(minutes: 10),
      (_) => unawaited(_syncIfConnected()),
    );
    _syncQueueSubscription ??= _syncQueueRepository.watchPending().listen((
      commands,
    ) {
      if (!commands.any(_isTaskCommand)) {
        return;
      }
      _localChangeDebounce?.cancel();
      _localChangeDebounce = Timer(
        const Duration(seconds: 1),
        () => unawaited(_syncIfConnected()),
      );
    });
    unawaited(_syncIfConnected());
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _localChangeDebounce?.cancel();
    unawaited(_syncQueueSubscription?.cancel());
    _timer = null;
    _localChangeDebounce = null;
    _syncQueueSubscription = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncIfConnected());
    }
  }

  Future<void> _syncIfConnected() async {
    final connection = await _integrationRepository.getConnection();
    if (connection?.calendarId == null ||
        connection?.status == 'disconnected') {
      return;
    }
    try {
      await _syncController.syncNow();
    } catch (_) {
      // The controller stores the error in Drift for the settings UI.
    }
  }

  bool _isTaskCommand(SyncCommandRow command) {
    return command.type.startsWith('task.');
  }
}
