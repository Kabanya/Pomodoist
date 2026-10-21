#ifndef MVD_LINUX_TASKBAR_MENU_H_
#define MVD_LINUX_TASKBAR_MENU_H_

#include <flutter_linux/flutter_linux.h>

// Binds the plugin method channel used to emit taskbarMenuItemSelected.
void mvd_linux_taskbar_menu_set_channel(FlMethodChannel* channel);

// Installs GtkApplication actions and syncs a user .desktop file so GNOME /
// other freedesktop shells can show taskbar / dock context menu entries.
void mvd_linux_set_taskbar_menu(FlValue* items);

#endif  // MVD_LINUX_TASKBAR_MENU_H_
