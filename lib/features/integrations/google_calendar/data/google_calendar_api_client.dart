import 'package:dio/dio.dart';

import '../domain/google_calendar_event.dart';
import 'google_calendar_config.dart';

abstract interface class GoogleCalendarApiClient {
  Future<GoogleCalendarApiCalendar> createCalendar(String name);
  Future<GoogleCalendarApiCalendar> getCalendar(String calendarId);
  Future<GoogleCalendarListResult> listEvents({
    required String calendarId,
    String? syncToken,
    String? pageToken,
  });
  Future<GoogleCalendarEvent> insertEvent({
    required String calendarId,
    required GoogleCalendarEvent event,
  });
  Future<GoogleCalendarEvent> patchEvent({
    required String calendarId,
    required String eventId,
    required GoogleCalendarEvent event,
  });
  Future<void> deleteEvent({
    required String calendarId,
    required String eventId,
  });
}

class GoogleCalendarApiCalendar {
  const GoogleCalendarApiCalendar({required this.id, required this.summary});

  final String id;
  final String summary;

  factory GoogleCalendarApiCalendar.fromJson(Map<String, Object?> json) {
    return GoogleCalendarApiCalendar(
      id: json['id'] as String,
      summary: (json['summary'] as String?) ?? 'Pomodoist',
    );
  }
}

class DioGoogleCalendarApiClient implements GoogleCalendarApiClient {
  DioGoogleCalendarApiClient({
    required Future<String?> Function({bool interactive}) accessTokenProvider,
    Dio? dio,
    Duration requestTimeout = googleCalendarRequestTimeout,
  }) : _accessTokenProvider = accessTokenProvider,
       _requestTimeout = requestTimeout,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: 'https://www.googleapis.com/calendar/v3',
               responseType: ResponseType.json,
               connectTimeout: requestTimeout,
               sendTimeout: requestTimeout,
               receiveTimeout: requestTimeout,
             ),
           );

  final Future<String?> Function({bool interactive}) _accessTokenProvider;
  final Duration _requestTimeout;
  final Dio _dio;

  @override
  Future<GoogleCalendarApiCalendar> createCalendar(String name) async {
    final response = await _request<Map<String, Object?>>(
      () => _dio.post('/calendars', data: {'summary': name}),
      interactiveAuth: true,
    );
    return GoogleCalendarApiCalendar.fromJson(response);
  }

  @override
  Future<GoogleCalendarApiCalendar> getCalendar(String calendarId) async {
    final response = await _request<Map<String, Object?>>(
      () => _dio.get('/calendars/${Uri.encodeComponent(calendarId)}'),
    );
    return GoogleCalendarApiCalendar.fromJson(response);
  }

  @override
  Future<GoogleCalendarListResult> listEvents({
    required String calendarId,
    String? syncToken,
    String? pageToken,
  }) async {
    final query = <String, Object?>{'showDeleted': 'true', 'maxResults': 2500};
    if (syncToken != null) {
      query['syncToken'] = syncToken;
    }
    if (pageToken != null) {
      query['pageToken'] = pageToken;
    }
    final response = await _request<Map<String, Object?>>(
      () => _dio.get(
        '/calendars/${Uri.encodeComponent(calendarId)}/events',
        queryParameters: query,
      ),
    );
    final items = response['items'] is List
        ? response['items']! as List
        : const [];
    return GoogleCalendarListResult(
      events: items
          .whereType<Map>()
          .map(
            (item) =>
                GoogleCalendarEvent.fromJson(Map<String, Object?>.from(item)),
          )
          .toList(),
      nextPageToken: response['nextPageToken'] as String?,
      nextSyncToken: response['nextSyncToken'] as String?,
    );
  }

  @override
  Future<GoogleCalendarEvent> insertEvent({
    required String calendarId,
    required GoogleCalendarEvent event,
  }) async {
    final response = await _request<Map<String, Object?>>(
      () => _dio.post(
        '/calendars/${Uri.encodeComponent(calendarId)}/events',
        queryParameters: {'sendUpdates': 'none'},
        data: event.toJson(),
      ),
    );
    return GoogleCalendarEvent.fromJson(response);
  }

  @override
  Future<GoogleCalendarEvent> patchEvent({
    required String calendarId,
    required String eventId,
    required GoogleCalendarEvent event,
  }) async {
    final response = await _request<Map<String, Object?>>(
      () => _dio.patch(
        '/calendars/${Uri.encodeComponent(calendarId)}/events/'
        '${Uri.encodeComponent(eventId)}',
        queryParameters: {'sendUpdates': 'none'},
        data: event.toJson(),
      ),
    );
    return GoogleCalendarEvent.fromJson(response);
  }

  @override
  Future<void> deleteEvent({
    required String calendarId,
    required String eventId,
  }) async {
    await _request<Object?>(
      () => _dio.delete(
        '/calendars/${Uri.encodeComponent(calendarId)}/events/'
        '${Uri.encodeComponent(eventId)}',
        queryParameters: {'sendUpdates': 'none'},
      ),
      ignoreNotFound: true,
    );
  }

  Future<T> _request<T>(
    Future<Response<Object?>> Function() request, {
    bool interactiveAuth = false,
    bool ignoreNotFound = false,
  }) async {
    final token = await _accessTokenProvider(interactive: interactiveAuth)
        .timeout(
          interactiveAuth
              ? googleCalendarInteractiveAuthTimeout
              : _requestTimeout,
        );
    if (token == null) {
      throw const GoogleCalendarAuthRequiredException();
    }
    _dio.options.headers['Authorization'] = 'Bearer $token';
    try {
      final response = await request().timeout(_requestTimeout);
      if (response.data == null) {
        return null as T;
      }
      return response.data! as T;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      if (ignoreNotFound && (statusCode == 404 || statusCode == 410)) {
        return null as T;
      }
      if (statusCode == 400) {
        throw GoogleCalendarApiException(
          googleCalendarApiErrorMessage(error.response?.data, statusCode),
        );
      }
      if (statusCode == 401) {
        throw const GoogleCalendarAuthRequiredException();
      }
      if (statusCode == 403) {
        throw GoogleCalendarApiException(
          googleCalendarApiErrorMessage(error.response?.data, statusCode),
        );
      }
      if (statusCode == 410) {
        throw const GoogleCalendarSyncTokenExpiredException();
      }
      rethrow;
    }
  }
}

class GoogleCalendarAuthRequiredException implements Exception {
  const GoogleCalendarAuthRequiredException();

  @override
  String toString() => 'Google Calendar authorization is required.';
}

class GoogleCalendarApiException implements Exception {
  const GoogleCalendarApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

String googleCalendarApiErrorMessage(Object? data, int? statusCode) {
  if (data is Map) {
    final error = data['error'];
    if (error is Map) {
      final status = error['status'];
      final message = error['message'];
      if (status is String && message is String && message.isNotEmpty) {
        return 'Google Calendar API failed: $status: $message';
      }
      if (message is String && message.isNotEmpty) {
        return 'Google Calendar API failed: $message';
      }
    }
  }
  if (data is String && data.trim().isNotEmpty) {
    return 'Google Calendar API failed: ${data.trim()}';
  }
  if (statusCode != null) {
    return 'Google Calendar API failed with HTTP $statusCode.';
  }
  return 'Google Calendar API failed.';
}

class GoogleCalendarSyncTokenExpiredException implements Exception {
  const GoogleCalendarSyncTokenExpiredException();

  @override
  String toString() => 'Google Calendar sync token expired.';
}
