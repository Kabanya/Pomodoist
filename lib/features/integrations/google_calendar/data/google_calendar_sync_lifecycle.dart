import 'dart:async';

import 'package:flutter/widgets.dart';

import 'google_calendar_repository.dart';
import 'google_calendar_sync_controller.dart';

class GoogleCalendarSyncLifecycle with WidgetsBindingObserver {
  GoogleCalendarSyncLifecycle({
    required CalendarIntegrationRepository integrationRepository,
    required GoogleCalendarSyncController syncController,
  }) : _integrationRepository = integrationRepository,
       _syncController = syncController;

  final CalendarIntegrationRepository _integrationRepository;
  final GoogleCalendarSyncController _syncController;
  Timer? _timer;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _timer ??= Timer.periodic(
      const Duration(minutes: 10),
      (_) => unawaited(_syncIfConnected()),
    );
    unawaited(_syncIfConnected());
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
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
}
