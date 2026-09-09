import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'theme_image_store_contract.dart';

ThemeImageStore createThemeImageStore() => BrowserThemeImageStore();

class BrowserThemeImageStore extends ThemeImageStore {
  Future<web.IDBDatabase>? _database;

  web.LockManager? get _locks =>
      web.window.navigator.getProperty<web.LockManager?>('locks'.toJS);

  @override
  Future<T> protect<T>(Future<T> Function() action) async {
    final locks = _locks;
    if (locks == null) return action();
    late Future<T> operation;
    await locks
        .request(
          'pomodoist-theme-settings',
          ((web.Lock lock) {
            operation = Future<T>.sync(action);
            // The promise holds the lock; returning the Dart Future below preserves
            // the original result or exception across the JavaScript boundary.
            return operation
                .then<JSAny?>(
                  (_) => null,
                  onError: (Object error, StackTrace stack) => null,
                )
                .toJS;
          }).toJS,
        )
        .toDart;
    return operation;
  }

  Future<web.IDBDatabase> _open() async {
    try {
      final result = Completer<web.IDBDatabase>();
      final request = web.window.indexedDB.open('pomodoist_theme_images', 1);
      request.onupgradeneeded = ((web.Event event) {
        (request.result as web.IDBDatabase).createObjectStore('images');
      }).toJS;
      request.onerror = ((web.Event event) {
        result.completeError(
          StateError(request.error?.message ?? 'Cannot open theme images'),
        );
      }).toJS;
      request.onsuccess = ((web.Event event) {
        final database = request.result as web.IDBDatabase;
        final opening = _database;
        void invalidate() {
          if (identical(_database, opening)) _database = null;
          database.close();
        }

        database.onversionchange = ((web.Event event) => invalidate()).toJS;
        database.onclose = ((web.Event event) => invalidate()).toJS;
        result.complete(database);
      }).toJS;
      return await result.future;
    } catch (_) {
      _database = null;
      rethrow;
    }
  }

  Future<void> _run(
    String mode,
    void Function(web.IDBObjectStore) action,
  ) async {
    final opening = _database ??= _open();
    final database = await opening;
    try {
      final transaction = database.transaction(
        'images'.toJS,
        mode,
        web.IDBTransactionOptions(durability: 'strict'),
      );
      try {
        action(transaction.objectStore('images'));
      } catch (_) {
        transaction.abort();
        rethrow;
      }
      final completed = Completer<void>();
      transaction.oncomplete = ((web.Event event) => completed.complete()).toJS;
      transaction.onabort = ((web.Event event) {
        completed.completeError(
          StateError(
            transaction.error?.message ?? 'Theme image transaction aborted',
          ),
        );
      }).toJS;
      await completed.future;
    } catch (_) {
      if (identical(_database, opening)) _database = null;
      database.close();
      rethrow;
    }
  }

  @override
  Future<Uint8List?> read(String id) async {
    validateThemeImageId(id);
    late web.IDBRequest request;
    await _run('readonly', (store) => request = store.get(id.toJS));
    final value = request.result;
    if (value.isUndefinedOrNull) return null;
    if (!value.isA<JSUint8Array>()) {
      throw const FormatException('Invalid stored theme image');
    }
    return Uint8List.fromList((value as JSUint8Array).toDart);
  }

  @override
  Future<void> write(String id, Uint8List bytes) async {
    validateThemeImageId(id);
    await _run('readwrite', (store) => store.put(bytes.toJS, id.toJS));
  }

  @override
  Future<void> retain(Set<String> ids) async {
    ids.forEach(validateThemeImageId);
    // ponytail: without cross-tab locking, a stale snapshot could delete
    // another tab's new photo. Keep files until Web Locks are available.
    if (_locks == null) return;
    await _run('readwrite', (store) {
      final request = store.getAllKeys();
      // Enqueue deletions in this callback while the transaction is active.
      request.onsuccess = ((web.Event event) {
        try {
          for (final key in (request.result as JSArray<JSAny?>).toDart) {
            if (key.isA<JSString>()) {
              final id = (key as JSString).toDart;
              if (isThemeImageId(id) && !ids.contains(id)) store.delete(key);
            }
          }
        } catch (_) {
          store.transaction.abort();
        }
      }).toJS;
    });
  }
}
