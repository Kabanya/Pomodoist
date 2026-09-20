import 'package:pomodoist/domain/models/platform/global_shortcut.dart';

extension GlobalShortcutWire on GlobalQuickAddBinding {
  String get portalTrigger => [
    if (control) 'CTRL',
    if (alt) 'ALT',
    if (shift) 'SHIFT',
    if (meta) 'LOGO',
    switch (keyLabel.toLowerCase()) {
      'enter' => 'Return',
      'escape' || 'esc' => 'Escape',
      'page up' => 'Page_Up',
      'page down' => 'Page_Down',
      final key => key,
    },
  ].join('+');

  Map<String, Object> toJson() => {
    'keyCode': keyCode,
    'keyLabel': keyLabel,
    'meta': meta,
    'control': control,
    'alt': alt,
    'shift': shift,
  };
}

GlobalQuickAddBinding decodeGlobalShortcut(Object? value) {
  if (value is! Map) {
    throw const FormatException('Missing macOS shortcut payload.');
  }
  final keyCode = value['keyCode'];
  final keyLabel = value['keyLabel'];
  final meta = value['meta'];
  final control = value['control'];
  final alt = value['alt'];
  final shift = value['shift'];
  if (keyCode is! int ||
      keyLabel is! String ||
      meta is! bool ||
      control is! bool ||
      alt is! bool ||
      shift is! bool) {
    throw const FormatException('Invalid macOS shortcut payload.');
  }
  return GlobalQuickAddBinding(
    keyCode: keyCode,
    keyLabel: keyLabel,
    meta: meta,
    control: control,
    alt: alt,
    shift: shift,
  );
}
