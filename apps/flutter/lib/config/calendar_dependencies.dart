import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/calendar/provider_calendar_models.dart';
import 'package:pomodoist/data/repositories/calendar/provider_calendar_repository.dart';
import 'package:pomodoist/data/services/google_calendar/google_calendar_sync_controller.dart';
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

final providerCalendarRepositoryProvider = Provider<ProviderCalendarRepository>(
  (ref) => ProviderCalendarRepository(ref.watch(appDatabaseProvider)),
);
final calendarConnectionsProvider = StreamProvider<List<CalendarConnection>>(
  (ref) => ref.watch(providerCalendarRepositoryProvider).watchConnections(),
);
final calendarLinksProvider =
    StreamProvider.family<List<CalendarEventLink>, String>(
      (ref, taskId) => ref
          .watch(providerCalendarRepositoryProvider)
          .watchLinksForTask(taskId),
    );
final calendarSyncRepositoryProvider =
    Provider.family<GoogleCalendarSyncRepository, CalendarProvider>((
      ref,
      provider,
    ) {
      if (provider == CalendarProvider.google) {
        return ref.watch(googleCalendarSyncRepositoryProvider);
      }
      final controller = GoogleCalendarSyncController(
        invoke: (body) {
          final account = ref.read(accountClientProvider);
          if (account?.currentUserId == null) {
            throw const GoogleCalendarServerException(
              'Authentication required.',
              code: 'auth_required',
            );
          }
          return account!.invokeFunction(
            'pomodoist-outlook-calendar',
            body: body,
          );
        },
      );
      return GoogleCalendarServerSyncRepository(controller);
    });
