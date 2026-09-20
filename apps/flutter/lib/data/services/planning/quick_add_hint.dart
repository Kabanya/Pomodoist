import 'dart:convert';

import 'package:pomodoist/domain/models/planning/quick_add_hint.dart';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

const deepSeekQuickAddHintModel = 'deepseek-v4-flash';

abstract interface class QuickAddHintGenerator {
  Future<String> generate({
    required List<String> recentTaskTitles,
    required String locale,
  });
}

class DeepSeekQuickAddHintGenerator implements QuickAddHintGenerator {
  DeepSeekQuickAddHintGenerator({
    required String apiKey,
    Dio? dio,
    Uri? endpoint,
    Duration timeout = const Duration(seconds: 25),
  }) : _apiKey = apiKey.trim(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: timeout,
               receiveTimeout: timeout,
               sendTimeout: timeout,
             ),
           ),
       _endpoint =
           endpoint ?? Uri.parse('https://api.deepseek.com/chat/completions');

  final String _apiKey;
  final Dio _dio;
  final Uri _endpoint;

  @override
  Future<String> generate({
    required List<String> recentTaskTitles,
    required String locale,
  }) async {
    if (_apiKey.isEmpty) {
      throw const QuickAddHintException('DeepSeek API key is not configured.');
    }
    final response = await _dio.postUri<Object?>(
      _endpoint,
      options: Options(
        contentType: Headers.jsonContentType,
        headers: <String, String>{'Authorization': 'Bearer $_apiKey'},
      ),
      data: buildDeepSeekQuickAddHintRequest(
        recentTaskTitles: recentTaskTitles,
        locale: locale,
      ),
    );
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw QuickAddHintException('DeepSeek request failed ($status).');
    }
    final hint = decodeDeepSeekQuickAddHintResponse(response.data);
    if (hint == null) {
      throw const QuickAddHintException('DeepSeek returned an invalid hint.');
    }
    return hint;
  }
}

Map<String, Object?> buildDeepSeekQuickAddHintRequest({
  required List<String> recentTaskTitles,
  required String locale,
}) {
  final titles = recentTaskTitles
      .map((title) => title.trim())
      .where((title) => title.isNotEmpty)
      .take(quickAddHintHistoryLimit)
      .toList(growable: false);
  if (titles.isEmpty) {
    throw const QuickAddHintException('No task titles are available.');
  }
  return <String, Object?>{
    'model': deepSeekQuickAddHintModel,
    'temperature': 0.3,
    'response_format': <String, String>{'type': 'json_object'},
    'messages': <Map<String, String>>[
      <String, String>{'role': 'system', 'content': _systemPrompt},
      <String, String>{
        'role': 'user',
        'content':
            'Locale: $locale\n\nRecent task titles:\n'
            '${titles.map((title) => '- $title').join('\n')}',
      },
    ],
  };
}

const _systemPrompt = '''
Create one short, ready-to-add task suggestion for Pomodoist from the user's recent task titles.
Return only JSON: {"hint":"..."}.

Rules:
- Use the requested locale.
- Return exactly one natural task title, at most 120 characters, on one line.
- Reflect the user's recent work without copying a title verbatim and without inventing facts.
- Include a valid 24-hour time token in HH:mm format, such as 14:30.
- Include exactly one project token in #project form and exactly one label token in @label form. Tokens cannot contain spaces.
- The result must be ready to paste into quick add. Do not use Markdown, comments, priorities, or focus estimates.
''';

String? decodeDeepSeekQuickAddHintResponse(Object? payload) {
  if (payload is! Map) {
    return null;
  }
  final choices = payload['choices'];
  if (choices is! List || choices.isEmpty || choices.first is! Map) {
    return null;
  }
  final message = (choices.first as Map)['message'];
  if (message is! Map || message['content'] is! String) {
    return null;
  }
  return decodeQuickAddHintJson(message['content'] as String);
}

String? decodeQuickAddHintJson(String content) {
  final text = content.trim();
  if (text.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(text);
    final hint = decoded is Map ? decoded['hint'] : null;
    return hint is String ? normalizeQuickAddHint(hint) : null;
  } on FormatException {
    return null;
  }
}

abstract interface class QuickAddHintHistory {
  Future<int> countExistingUserTasks();

  Future<List<String>> recentTaskTitles({required int limit});
}

class DriftQuickAddHintHistory implements QuickAddHintHistory {
  DriftQuickAddHintHistory(this._db);

  final AppDatabase _db;

  @override
  Future<int> countExistingUserTasks() async {
    final rows = await _db.select(_db.tasks).get();
    return rows.length;
  }

  @override
  Future<List<String>> recentTaskTitles({required int limit}) async {
    final rows =
        await (_db.select(_db.tasks)
              ..where((task) => task.isDeleted.equals(false))
              ..orderBy([
                (task) => OrderingTerm(
                  expression: task.createdAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(limit))
            .get();
    return rows
        .map((task) => task.content.trim())
        .where((title) => title.isNotEmpty)
        .take(limit)
        .toList(growable: false);
  }
}

abstract interface class QuickAddHintStore {
  Future<QuickAddHintState?> read();

  Future<void> write(QuickAddHintState state);
}

const _quickAddHintCreatedTaskCountKey = 'quickAdd.hint.createdTaskCount';
const _quickAddHintNextRefreshKey = 'quickAdd.hint.nextRefreshAt';
const _quickAddHintRetryPendingKey = 'quickAdd.hint.retryPending';
const _quickAddHintRecentKey = 'quickAdd.hint.recent';
const _quickAddHintStarterConsumedKey = 'quickAdd.hint.starterConsumed';
const _quickAddHintTextKey = 'quickAdd.hint.text';
const _quickAddHintLocaleKey = 'quickAdd.hint.locale';

class SharedPreferencesQuickAddHintStore implements QuickAddHintStore {
  SharedPreferencesQuickAddHintStore(this._preferences);

  final Future<SharedPreferences?> Function() _preferences;

  @override
  Future<QuickAddHintState?> read() async {
    final preferences = await _preferences();
    final count = preferences?.getInt(_quickAddHintCreatedTaskCountKey);
    final nextRefreshAt = preferences?.getInt(_quickAddHintNextRefreshKey);
    if (count == null || nextRefreshAt == null) {
      return null;
    }
    final savedHintsRaw = preferences?.getString(_quickAddHintRecentKey);
    final legacyHintRaw = preferences?.getString(_quickAddHintTextKey);
    return QuickAddHintState(
      createdTaskCount: count,
      nextRefreshAt: nextRefreshAt,
      retryPending: preferences?.getBool(_quickAddHintRetryPendingKey) ?? false,
      starterConsumed:
          preferences?.getBool(_quickAddHintStarterConsumedKey) ??
          (savedHintsRaw?.isNotEmpty == true ||
              legacyHintRaw?.isNotEmpty == true),
      recentHints: _decodeSavedQuickAddHints(savedHintsRaw),
    );
  }

  @override
  Future<void> write(QuickAddHintState state) async {
    final preferences = await _preferences();
    if (preferences == null) {
      return;
    }
    await Future.wait([
      preferences.setInt(
        _quickAddHintCreatedTaskCountKey,
        state.createdTaskCount,
      ),
      preferences.setInt(_quickAddHintNextRefreshKey, state.nextRefreshAt),
      preferences.setBool(_quickAddHintRetryPendingKey, state.retryPending),
      preferences.setBool(
        _quickAddHintStarterConsumedKey,
        state.starterConsumed,
      ),
      preferences.setString(
        _quickAddHintRecentKey,
        jsonEncode(state.recentHints.map((hint) => hint.toJson()).toList()),
      ),
      preferences.remove(_quickAddHintTextKey),
      preferences.remove(_quickAddHintLocaleKey),
    ]);
  }
}

List<QuickAddHint> _decodeSavedQuickAddHints(String? encoded) {
  if (encoded == null || encoded.isEmpty) {
    return const [];
  }
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      return const [];
    }
    return retainRecentQuickAddHints(
      decoded.whereType<Map>().map((item) {
        final text = item['text'];
        final locale = item['locale'];
        final normalizedText = text is String
            ? normalizeQuickAddHint(text)
            : null;
        return normalizedText != null && locale is String && locale.isNotEmpty
            ? QuickAddHint(text: normalizedText, locale: locale)
            : null;
      }).whereType<QuickAddHint>(),
    );
  } on FormatException {
    return const [];
  }
}
