import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../core/db/app_database.dart';
import 'google_calendar_sync_controller.dart';

class GoogleCalendarSyncLifecycle with WidgetsBindingObserver {
  GoogleCalendarSyncLifecycle({
    required Stream<GoogleCalendarConnectionRow?> connections,
    required GoogleCalendarSyncController syncController,
  }) : _connections = connections,
       _syncController = syncController;

  final Stream<GoogleCalendarConnectionRow?> _connections;
  final GoogleCalendarSyncController _syncController;
  StreamSubscription<GoogleCalendarConnectionRow?>? _subscription;
  GoogleCalendarConnectionRow? _connection;
  bool _foreground = true;
  bool _requested = false;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _subscription ??= _connections.listen((connection) {
      _connection = connection;
      _syncIfConnected();
    });
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) return;
    _requested = false;
    _syncIfConnected();
  }

  void _syncIfConnected() {
    final connection = _connection;
    if (!_foreground ||
        _requested ||
        connection?.status != 'connected' ||
        connection?.calendarId == null) {
      return;
    }
    _requested = true;
    unawaited(_syncController.syncNow().catchError((_) {}));
  }
}
