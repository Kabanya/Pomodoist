import 'dart:async';
import 'dart:convert';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/pomo/pomo_models.dart';
import 'pomo_preferences_repository.dart';

class LocalPomoPreferencesRepository implements PomoPreferencesRepository {
  LocalPomoPreferencesRepository(this._preferences);
  static const key = 'pomo.preferences.v1';
  final PreferencesService _preferences;
  final _changes = StreamController<PomoPreferences>.broadcast(sync: true);
  @override
  Stream<PomoPreferences> get changes => _changes.stream;
  @override
  PomoPreferences state = const PomoPreferences();
  Future<void>? _loading;
  Future<void> _pending = Future.value();
  bool _disposed = false;
  @override
  Future<void> load() =>
      _loading ??= _load().catchError((Object error, StackTrace stack) {
        _loading = null;
        Error.throwWithStackTrace(error, stack);
      });
  Future<void> _load() async {
    final data = (await _preferences.read([key])).getOrThrow()[key];
    try {
      if (data is String) {
        state = PomoPreferences.fromJson(
          jsonDecode(data) as Map<String, dynamic>,
        );
      }
    } on FormatException {
      state = const PomoPreferences();
    } on TypeError {
      state = const PomoPreferences();
    }
    if (!_disposed) _changes.add(state);
  }

  /// Serialize read-modify-write operations, including drag and close races.
  @override
  Future<void> update(PomoPreferences Function(PomoPreferences) edit) {
    final result = _pending.then((_) async {
      await load();
      if (_disposed) return;
      final next = edit(state);
      (await _preferences.write({key: jsonEncode(next.toJson())})).getOrThrow();
      if (_disposed) return;
      state = next;
      _changes.add(state);
    });
    _pending = result.catchError((Object _) {});
    return result;
  }

  void dispose() {
    _disposed = true;
    unawaited(_changes.close());
  }
}
