import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:pomodoist/data/services/platform/linux_global_shortcuts.dart';

/// Double for [LinuxGlobalShortcutsPortal] that never reaches the session bus.
///
/// The base constructor still gets a client pointed at a socket that does not
/// exist, so anything the fake forgets to override fails loudly instead of
/// talking to the real desktop portal.
class FakeLinuxShortcutsPortal extends LinuxGlobalShortcutsPortal {
  FakeLinuxShortcutsPortal({this.available = true})
    : super(
        client: DBusClient(
          DBusAddress('unix:path=/tmp/pomodoist-unused-dbus'),
          authClient: DBusAuthClient(uid: '1000'),
        ),
        sandboxed: false,
        manageHyprlandShortcut: false,
      );

  /// Answer of [isAvailable].
  bool available;

  /// Number of [disable] calls.
  int disableCalls = 0;

  /// `preferredTrigger` of the last [enable] call.
  String? enabledTrigger;

  /// `onActivated` of the last [enable] call, for a test to invoke directly.
  FutureOr<void> Function()? activationCallback;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> enable({
    required String preferredTrigger,
    required FutureOr<void> Function() onActivated,
  }) async {
    enabledTrigger = preferredTrigger;
    activationCallback = onActivated;
  }

  @override
  Future<void> disable() async {
    disableCalls++;
  }

  @override
  Future<void> dispose() async {}
}
