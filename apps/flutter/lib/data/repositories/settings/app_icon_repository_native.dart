import 'dart:io';

import 'package:flutter/services.dart' hide appFlavor;
import 'package:pomodoist/data/repositories/settings/app_icon_repository.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';
import 'package:pomodoist/domain/models/settings/app_icon_choice.dart';

class PlatformAppIconRepository implements AppIconRepository {
  static const _channel = MethodChannel('pomodoist/app_icon');

  @override
  Future<AppIconChoice> read() async {
    final id = await _channel.invokeMethod<String>('getIcon');
    if (!AppIconChoice.values.any((choice) => choice.id == id)) {
      throw StateError('Unsupported native app icon: $id');
    }
    return AppIconChoice.fromId(id);
  }

  @override
  Future<void> apply(AppIconChoice choice) async {
    final arguments = <String, Object>{'icon': choice.id};
    if (Platform.isMacOS) {
      final data = await rootBundle.load(
        'assets/branding/app_icons/generated/${appFlavor.name}/${choice.id}-macos.png',
      );
      arguments['image'] = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    }
    await _channel.invokeMethod<void>('setIcon', arguments);
  }
}
