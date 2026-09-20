import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/data/repositories/calendar/google_calendar_server_sync_repository.dart';
import 'package:pomodoist/data/repositories/calendar/google_calendar_sync_repository.dart';

final googleCalendarSyncRepositoryProvider =
    Provider<GoogleCalendarSyncRepository>(
      (ref) => GoogleCalendarServerSyncRepository(
        ref.watch(googleCalendarSyncControllerProvider),
      ),
    );
