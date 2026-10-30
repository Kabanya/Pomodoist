import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pomodoist/data/repositories/settings/status_item_style_repository.dart';
import 'package:pomodoist/domain/models/settings/status_item_style.dart';

class NativeStatusItemStyleRepository implements StatusItemStyleRepository {
  NativeStatusItemStyleRepository() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'styleChanged') {
        for (final style in StatusItemStyle.values) {
          if (style.name == call.arguments) _changes.add(style);
        }
      }
    });
  }

  static const _channel = MethodChannel('pomodoist/status_item');
  final _changes = StreamController<StatusItemStyle>.broadcast(sync: true);

  @override
  Stream<StatusItemStyle> get changes => _changes.stream;

  @override
  Future<StatusItemStyle> read() async =>
      _decode(await _channel.invokeMethod<String>('getStyle'));

  @override
  Future<StatusItemStyle> select(StatusItemStyle style) async =>
      _decode(await _channel.invokeMethod<String>('setStyle', style.name));

  static StatusItemStyle _decode(String? value) =>
      StatusItemStyle.values.firstWhere(
        (style) => style.name == value,
        orElse: () =>
            throw StateError('Unsupported menu bar timer style: $value'),
      );

  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_changes.close());
  }
}
