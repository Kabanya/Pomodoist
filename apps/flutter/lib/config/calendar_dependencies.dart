import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/data/repositories/calendar/google_calendar_sync_repository.dart';

final googleCalendarSyncRepositoryProvider = Provider(
  (ref) => GoogleCalendarSyncRepository(
    ref.watch(googleCalendarSyncControllerProvider),
  ),
);
