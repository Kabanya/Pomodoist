import 'dart:convert';

import 'package:flutter/services.dart';

/// Custom entry for the app taskbar / dock context menu.
///
/// On Windows and macOS, [iconAsset] is used when provided. Linux shows [title] only.
///
/// On Linux (GNOME / freedesktop), items are exposed through `.desktop` Actions
/// in the dock context menu. See the Linux setup notes in the package README.
class TaskbarMenuItem {
  const TaskbarMenuItem({
    required this.title,
    this.iconAsset,
    this.onPressed,
  });

  /// Visible menu label.
  final String title;

  /// Flutter asset path (e.g. `assets/icons/new_window.png`). Optional; used on Windows and macOS.
  final String? iconAsset;

  /// Invoked when the user selects this item. Matched by list index on the Dart side.
  final VoidCallback? onPressed;

  /// Serializes this item for the native taskbar / dock menu channel.
  ///
  /// [id] is the item index in the menu list; native uses it to report selection back to Dart.
  Future<Map<String, dynamic>> toJson(int id) async {
    final map = <String, dynamic>{'id': id, 'title': title};
    final asset = iconAsset;
    if (asset != null) {
      final byteData = await rootBundle.load(asset);
      map['icon'] = base64Encode(
        byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
      );
    }
    return map;
  }
}
