import 'dart:convert';
import 'dart:io';

const hyprlandManagedShortcutDescription = 'Pomodoist managed global quick add';

typedef HyprlandCommandRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class HyprlandShortcutConflict implements Exception {
  const HyprlandShortcutConflict(this.shortcut);

  final String shortcut;

  @override
  String toString() => 'The Hyprland shortcut $shortcut is already in use.';
}

class HyprlandShortcutCleanupConflict implements Exception {
  const HyprlandShortcutCleanupConflict(this.shortcut);

  final String shortcut;

  @override
  String toString() =>
      'The managed Hyprland shortcut $shortcut now also contains a user bind.';
}

class HyprlandGlobalShortcut {
  HyprlandGlobalShortcut({HyprlandCommandRunner commandRunner = _runCommand})
    : _commandRunner = commandRunner;

  final HyprlandCommandRunner _commandRunner;

  static Future<ProcessResult> _runCommand(
    String executable,
    List<String> arguments,
  ) {
    return Process.run(executable, arguments);
  }

  Future<void> replace({
    required String portalTrigger,
    required String appId,
  }) async {
    final target = _HyprlandShortcut.parse(portalTrigger);
    final binds = await _readBinds();
    final targetBinds = _atShortcut(binds, target).toList();
    if (targetBinds.any((bind) => !_isManagedBinding(bind))) {
      throw HyprlandShortcutConflict(target.keys);
    }

    final managed = _managedShortcuts(binds);
    _ensureManagedShortcutsCanBeRemoved(binds, managed);
    final action = '$appId:quick-add';
    final managedAtTarget = managed
        .where((entry) => entry.shortcut.sameAs(target))
        .toList();
    final targetIsCurrent =
        managedAtTarget.length == 1 && managedAtTarget.single.action == action;

    if (managedAtTarget.isNotEmpty && !targetIsCurrent) {
      await _unbind(target);
    }
    if (!targetIsCurrent) {
      await _bind(target, action);
    }

    final removed = <String>{};
    for (final entry in managed) {
      if (entry.shortcut.sameAs(target)) continue;
      if (removed.add(entry.shortcut.identity)) {
        await _unbind(entry.shortcut);
      }
    }
  }

  Future<void> remove() async {
    final binds = await _readBinds();
    final managed = _managedShortcuts(binds);
    _ensureManagedShortcutsCanBeRemoved(binds, managed);
    final removed = <String>{};
    for (final entry in managed) {
      if (removed.add(entry.shortcut.identity)) {
        await _unbind(entry.shortcut);
      }
    }
  }

  Future<List<Map<dynamic, dynamic>>> _readBinds() async {
    final result = await _commandRunner('hyprctl', ['binds', '-j']);
    _requireExitSuccess(result, 'read Hyprland keybinds');
    final decoded = jsonDecode(result.stdout?.toString() ?? '');
    if (decoded is! List) {
      throw const FormatException('hyprctl binds returned invalid JSON.');
    }
    return decoded.whereType<Map>().toList();
  }

  Iterable<Map<dynamic, dynamic>> _atShortcut(
    Iterable<Map<dynamic, dynamic>> binds,
    _HyprlandShortcut shortcut,
  ) {
    return binds.where((bind) {
      final existing = _shortcutFromBind(bind);
      return existing != null && existing.sameAs(shortcut);
    });
  }

  List<_ManagedShortcut> _managedShortcuts(
    Iterable<Map<dynamic, dynamic>> binds,
  ) {
    final managed = <_ManagedShortcut>[];
    for (final bind in binds) {
      if (!_isManagedBinding(bind)) continue;
      final shortcut = _shortcutFromBind(bind);
      if (shortcut == null) continue;
      managed.add(
        _ManagedShortcut(
          shortcut: shortcut,
          action: bind['arg']?.toString() ?? '',
        ),
      );
    }
    return managed;
  }

  void _ensureManagedShortcutsCanBeRemoved(
    List<Map<dynamic, dynamic>> binds,
    List<_ManagedShortcut> managed,
  ) {
    for (final entry in managed) {
      final hasUserBind = _atShortcut(
        binds,
        entry.shortcut,
      ).any((bind) => !_isManagedBinding(bind));
      if (hasUserBind) {
        throw HyprlandShortcutCleanupConflict(entry.shortcut.keys);
      }
    }
  }

  bool _isManagedBinding(Map<dynamic, dynamic> bind) {
    return bind['description'] == hyprlandManagedShortcutDescription &&
        bind['dispatcher']?.toString().toLowerCase() == 'global' &&
        bind['arg']?.toString().endsWith(':quick-add') == true;
  }

  _HyprlandShortcut? _shortcutFromBind(Map<dynamic, dynamic> bind) {
    final submap = bind['submap']?.toString().toLowerCase();
    final universal =
        bind['submap_universal'] == true ||
        bind['submap_universal']?.toString().toLowerCase() == 'true';
    if (submap != 'global' && !universal) return null;
    final modmask = bind['modmask'];
    final key = bind['key']?.toString();
    if (modmask is! num || key == null || key.isEmpty) return null;
    return _HyprlandShortcut.fromMask(modmask.toInt(), key);
  }

  Future<void> _bind(_HyprlandShortcut shortcut, String action) {
    return _keyword(
      'bindd',
      '${shortcut.keywordModifiers}, ${shortcut.key}, '
          '$hyprlandManagedShortcutDescription, global, $action',
    );
  }

  Future<void> _unbind(_HyprlandShortcut shortcut) {
    return _keyword('unbind', '${shortcut.keywordModifiers}, ${shortcut.key}');
  }

  Future<void> _keyword(String keyword, String value) async {
    final result = await _commandRunner('hyprctl', ['keyword', keyword, value]);
    _requireExitSuccess(result, 'update the Hyprland keybind');
    if (result.stdout.toString().trim() != 'ok') {
      throw ProcessException(
        'hyprctl',
        ['keyword', keyword, value],
        result.stdout.toString().trim(),
        result.exitCode,
      );
    }
  }

  void _requireExitSuccess(ProcessResult result, String operation) {
    if (result.exitCode == 0) return;
    final error = result.stderr.toString().trim();
    throw ProcessException(
      'hyprctl',
      const [],
      error.isEmpty ? 'Failed to $operation.' : error,
      result.exitCode,
    );
  }
}

class _ManagedShortcut {
  const _ManagedShortcut({required this.shortcut, required this.action});

  final _HyprlandShortcut shortcut;
  final String action;
}

class _HyprlandShortcut {
  const _HyprlandShortcut({required this.key, required this.modmask});

  final String key;
  final int modmask;

  String get keywordModifiers => _modifierNames(modmask).join(' ');
  String get keys => [..._modifierNames(modmask), key].join(' + ');
  String get identity => '$modmask:$key';

  bool sameAs(_HyprlandShortcut other) =>
      modmask == other.modmask &&
      _normalizeKey(key) == _normalizeKey(other.key);

  factory _HyprlandShortcut.fromMask(int modmask, String key) {
    return _HyprlandShortcut(key: _normalizeKey(key), modmask: modmask);
  }

  factory _HyprlandShortcut.parse(String portalTrigger) {
    final parts = portalTrigger
        .split('+')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      throw const FormatException('The global shortcut is empty.');
    }

    var modmask = 0;
    for (final part in parts.take(parts.length - 1)) {
      modmask |= switch (part.toUpperCase()) {
        'SHIFT' => 1,
        'CAPS' || 'CAPSLOCK' => 2,
        'CTRL' || 'CONTROL' => 4,
        'ALT' => 8,
        'MOD2' => 16,
        'MOD3' => 32,
        'LOGO' || 'META' || 'SUPER' || 'WIN' => 64,
        'MOD5' => 128,
        _ => throw FormatException('Unsupported shortcut modifier: $part'),
      };
    }

    final key = _normalizeKey(parts.last);
    if (key.isEmpty) {
      throw const FormatException('The global shortcut key is empty.');
    }
    return _HyprlandShortcut(key: key, modmask: modmask);
  }
}

List<String> _modifierNames(int modmask) => [
  if (modmask & 1 != 0) 'SHIFT',
  if (modmask & 2 != 0) 'CAPS',
  if (modmask & 4 != 0) 'CTRL',
  if (modmask & 8 != 0) 'ALT',
  if (modmask & 16 != 0) 'MOD2',
  if (modmask & 32 != 0) 'MOD3',
  if (modmask & 64 != 0) 'SUPER',
  if (modmask & 128 != 0) 'MOD5',
];

String _normalizeKey(String key) {
  final normalized = key.trim().replaceAll(' ', '_').replaceAll('-', '_');
  return switch (normalized.toUpperCase()) {
    'ENTER' => 'RETURN',
    'ESC' => 'ESCAPE',
    final value => value,
  };
}
