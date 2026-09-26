import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/calendar/google_calendar_sync_repository.dart';
import 'package:pomodoist/ui/google_calendar/view_models/google_calendar_view_model.dart';

void main() {
  test('Google request limits are distinguished from unavailable service', () {
    final model = GoogleCalendarViewModel();
    for (final status in [403, 429]) {
      final message = jsonEncode({
        'error': {
          'errors': [
            {
              'domain': 'usageLimits',
              'reason': 'rateLimitExceeded',
              'message': 'Rate Limit Exceeded',
            },
          ],
          'code': status,
          'message': 'Rate Limit Exceeded',
        },
      });
      expect(model.classify(message), CalendarFailure.rateLimited);
      expect(
        model.classify(
          GoogleCalendarFailure(GoogleCalendarFailureCode.unavailable, message),
        ),
        CalendarFailure.rateLimited,
      );
    }
  });

  test('per-user limits and classified failures retain their meaning', () {
    final model = GoogleCalendarViewModel();
    expect(
      model.classify(
        '{"error":{"errors":[{"reason":"userRateLimitExceeded"}]}}',
      ),
      CalendarFailure.rateLimited,
    );
    for (final failure in CalendarFailure.values) {
      expect(model.classify(failure), failure);
    }
  });

  test(
    'unrecognized errors stay generic and authorization stays actionable',
    () {
      final model = GoogleCalendarViewModel();
      for (final error in [
        '',
        '{invalid JSON',
        'null',
        '[]',
        '{"error":{"errors":null}}',
        '{"error":{"errors":[null,{},"rateLimitExceeded"]}}',
        '{"error":{"code":403,"errors":[{"reason":"forbidden"}]}}',
        Exception('private server details'),
      ]) {
        expect(model.classify(error), CalendarFailure.unavailable);
      }
      expect(
        model.classify(
          const GoogleCalendarFailure(
            GoogleCalendarFailureCode.authorizationRequired,
            'Sign in again.',
          ),
        ),
        CalendarFailure.authRequired,
      );
    },
  );
}
