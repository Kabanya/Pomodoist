import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

const deepSeekQuickAddHintModel = 'deepseek-v4-flash';
const quickAddHintHistoryLimit = 10;
const quickAddHintMaxLength = 120;

class QuickAddHintException implements Exception {
  const QuickAddHintException(this.message);

  final String message;

  @override
  String toString() => message;
}

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

String? normalizeQuickAddHint(String value) {
  final hint = value.trim();
  if (hint.isEmpty ||
      hint.length > quickAddHintMaxLength ||
      hint.contains(RegExp(r'[\r\n]'))) {
    return null;
  }
  final tokens = hint.split(RegExp(r'\s+'));
  if (tokens.where(_isQuickAddProjectToken).length != 1 ||
      tokens.where(_isQuickAddLabelToken).length != 1 ||
      tokens.where(_isQuickAddTimeToken).length != 1) {
    return null;
  }
  return hint;
}

bool _isQuickAddProjectToken(String token) =>
    RegExp(r'^#[^\s#@]+$').hasMatch(token);

bool _isQuickAddLabelToken(String token) =>
    RegExp(r'^@[^\s#@]+$').hasMatch(token);

bool _isQuickAddTimeToken(String token) =>
    RegExp(r'^(?:[01]?\d|2[0-3]):[0-5]\d$').hasMatch(token);

int firstQuickAddHintRefreshAt({required bool hasActiveEntitlement}) {
  return 1;
}

int nextQuickAddHintRefreshAfter(
  int createdTaskCount, {
  bool hasActiveEntitlement = true,
}) {
  if (!hasActiveEntitlement && createdTaskCount >= 1000) {
    return ((createdTaskCount ~/ 500) + 1) * 500;
  }
  if (createdTaskCount < 1) {
    return 1;
  }
  if (createdTaskCount < 10) {
    return 10;
  }
  if (createdTaskCount < 25) {
    return 25;
  }
  if (createdTaskCount < 50) {
    return 50;
  }
  return ((createdTaskCount ~/ 50) + 1) * 50;
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
const _quickAddHintMaxSavedHints = 5;

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

class QuickAddHint {
  const QuickAddHint({required this.text, required this.locale});

  final String text;
  final String locale;

  Map<String, String> toJson() => {'text': text, 'locale': locale};
}

List<QuickAddHint> retainRecentQuickAddHints(Iterable<QuickAddHint> hints) {
  final items = hints.toList(growable: false);
  final start = items.length > _quickAddHintMaxSavedHints
      ? items.length - _quickAddHintMaxSavedHints
      : 0;
  return List.unmodifiable(items.sublist(start));
}

String? selectRandomQuickAddHintForLocale(
  Iterable<QuickAddHint> hints,
  String locale, {
  int Function(int upperBound)? randomIndex,
}) {
  final matching = hints.where((hint) => hint.locale == locale).toList();
  if (matching.isEmpty) {
    return null;
  }
  final index = (randomIndex ?? _randomQuickAddHintIndex)(matching.length);
  return matching[index].text;
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

int _randomQuickAddHintIndex(int upperBound) => Random().nextInt(upperBound);

class QuickAddHintState {
  const QuickAddHintState({
    required this.createdTaskCount,
    required this.nextRefreshAt,
    required this.retryPending,
    this.starterConsumed = false,
    this.recentHints = const [],
  });

  final int createdTaskCount;
  final int nextRefreshAt;
  final bool retryPending;
  final bool starterConsumed;
  final List<QuickAddHint> recentHints;

  String? hintForLocale(
    String locale, {
    int Function(int upperBound)? randomIndex,
  }) {
    return selectRandomQuickAddHintForLocale(
      recentHints,
      locale,
      randomIndex: randomIndex,
    );
  }

  QuickAddHintState copyWith({
    int? createdTaskCount,
    int? nextRefreshAt,
    bool? retryPending,
    bool? starterConsumed,
    List<QuickAddHint>? recentHints,
  }) {
    return QuickAddHintState(
      createdTaskCount: createdTaskCount ?? this.createdTaskCount,
      nextRefreshAt: nextRefreshAt ?? this.nextRefreshAt,
      retryPending: retryPending ?? this.retryPending,
      starterConsumed: starterConsumed ?? this.starterConsumed,
      recentHints: recentHints ?? this.recentHints,
    );
  }
}

class QuickAddHintCoordinator {
  QuickAddHintCoordinator({
    required QuickAddHintHistory history,
    required QuickAddHintStore store,
    required QuickAddHintGenerator generator,
    required String Function() locale,
    bool Function()? hasActiveEntitlement,
    void Function(QuickAddHintState state)? onStateChanged,
  }) : _history = history,
       _store = store,
       _generator = generator,
       _locale = locale,
       _hasActiveEntitlement = hasActiveEntitlement ?? _alwaysPaid,
       _onStateChanged = onStateChanged;

  final QuickAddHintHistory _history;
  final QuickAddHintStore _store;
  final QuickAddHintGenerator _generator;
  final String Function() _locale;
  final bool Function() _hasActiveEntitlement;
  final void Function(QuickAddHintState state)? _onStateChanged;
  Future<void>? _initialization;
  var _refreshing = false;

  QuickAddHintState _state = const QuickAddHintState(
    createdTaskCount: 0,
    nextRefreshAt: 1,
    retryPending: false,
  );

  QuickAddHintState get state => _state;

  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> recordUserTaskCreated() async {
    await initialize();
    await _alignScheduleToEntitlement();
    _state = _state.copyWith(createdTaskCount: _state.createdTaskCount + 1);
    if (!_state.retryPending &&
        _state.createdTaskCount >= _state.nextRefreshAt) {
      _state = _state.copyWith(retryPending: true);
    }
    await _writeState();
    if (_state.retryPending) {
      await _refresh();
    }
  }

  String? hintForLocale(String locale) {
    return _state.hintForLocale(locale);
  }

  Future<void> _initialize() async {
    try {
      final stored = await _store.read();
      if (stored != null) {
        _state = stored;
      } else {
        final count = await _history.countExistingUserTasks();
        final hasActiveEntitlement = _hasActiveEntitlement();
        _state = QuickAddHintState(
          createdTaskCount: count,
          nextRefreshAt: nextQuickAddHintRefreshAfter(
            count,
            hasActiveEntitlement: hasActiveEntitlement,
          ),
          retryPending:
              count >=
              firstQuickAddHintRefreshAt(
                hasActiveEntitlement: hasActiveEntitlement,
              ),
        );
        await _writeState();
      }
      await _alignScheduleToEntitlement();
      if (!_state.retryPending &&
          _state.createdTaskCount >= _state.nextRefreshAt) {
        _state = _state.copyWith(retryPending: true);
        await _writeState();
      }
      if (_state.retryPending) {
        await _refresh();
      }
    } catch (_) {
      // A hint is optional and must never affect task creation or app startup.
    }
  }

  Future<void> _refresh() async {
    if (_refreshing || !_state.retryPending) {
      return;
    }
    _refreshing = true;
    final locale = _locale();
    try {
      final titles = await _history.recentTaskTitles(
        limit: quickAddHintHistoryLimit,
      );
      final hint = normalizeQuickAddHint(
        await _generator.generate(recentTaskTitles: titles, locale: locale),
      );
      if (hint == null) {
        throw const QuickAddHintException('DeepSeek returned an invalid hint.');
      }
      _state = _state.copyWith(
        starterConsumed: true,
        recentHints: retainRecentQuickAddHints([
          ..._state.recentHints,
          QuickAddHint(text: hint, locale: locale),
        ]),
        nextRefreshAt: nextQuickAddHintRefreshAfter(
          _state.createdTaskCount,
          hasActiveEntitlement: _hasActiveEntitlement(),
        ),
        retryPending: false,
      );
    } catch (_) {
      // Keep the previous hint and retry the same threshold on the next launch.
    } finally {
      _refreshing = false;
      await _writeState();
    }
  }

  Future<void> _writeState() async {
    await _store.write(_state);
    _onStateChanged?.call(_state);
  }

  Future<void> _alignScheduleToEntitlement() async {
    if (_state.retryPending) {
      return;
    }
    final nextRefreshAt = nextQuickAddHintRefreshAfter(
      _state.createdTaskCount,
      hasActiveEntitlement: _hasActiveEntitlement(),
    );
    if (_state.nextRefreshAt == nextRefreshAt) {
      return;
    }
    _state = _state.copyWith(nextRefreshAt: nextRefreshAt);
    await _writeState();
  }
}

bool _alwaysPaid() => true;
