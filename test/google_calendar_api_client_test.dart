import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/integrations/google_calendar/data/google_calendar_api_client.dart';

void main() {
  test('formats Google Calendar API error details', () {
    expect(
      googleCalendarApiErrorMessage({
        'error': {'status': 'INVALID_ARGUMENT', 'message': 'Bad Request'},
      }, 400),
      'Google Calendar API failed: INVALID_ARGUMENT: Bad Request',
    );
  });

  test('formats Google Calendar API permission errors', () {
    expect(
      googleCalendarApiErrorMessage({
        'error': {
          'status': 'PERMISSION_DENIED',
          'message': 'Google Calendar API has not been used in project.',
        },
      }, 403),
      'Google Calendar API failed: PERMISSION_DENIED: Google Calendar API '
      'has not been used in project.',
    );
  });
}
