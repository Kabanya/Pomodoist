import 'dart:async';

class LinuxGlobalShortcutsPortal {
  LinuxGlobalShortcutsPortal({
    Object? client,
    bool? sandboxed,
    bool manageHyprlandShortcut = true,
  });

  Future<bool> isAvailable() async => false;

  Future<void> enable({
    required String preferredTrigger,
    required FutureOr<void> Function() onActivated,
  }) => throw UnsupportedError('XDG GlobalShortcuts Portal is unavailable.');

  Future<void> disable() async {}

  Future<void> dispose() async {}
}
