#ifndef MVD_LINUX_GNOME_H_
#define MVD_LINUX_GNOME_H_
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <functional>
// All entry points run on the GTK main context; all D-Bus work is asynchronous.
bool mvd_gnome_context();
void mvd_gnome_start();
void mvd_gnome_shutdown();
bool mvd_gnome_available();
const char* mvd_gnome_reason();
void mvd_gnome_environment(FlValue* result);
FlValue* mvd_gnome_cursor();
void mvd_gnome_status(std::function<void()> done);
void mvd_gnome_install(bool install, std::function<void()> done);
void mvd_gnome_following(bool enabled, std::function<void(const char*)> done = {});
// Transport operations are independent of GTK realization. Callbacks borrow
// their decoded value for the duration of the callback.
void mvd_gnome_register_token(const char* token, const char* role,
    std::function<void(FlValue*, const char*)> done);
bool mvd_gnome_command_is_local(const char* method, FlValue* payload, bool registered);
void mvd_gnome_token_command(const char* token, const char* method, FlValue* payload,
    std::function<void(FlValue*, const char*)> done, bool registered = true);
void mvd_gnome_prepare(GtkWindow* window, const char* role);
bool mvd_gnome_window(GtkWindow* window);
bool mvd_gnome_show(GtkWindow* window);
void mvd_gnome_hide(GtkWindow* window);
FlValue* mvd_gnome_bounds(GtkWindow* window);
void mvd_gnome_configure(GtkWindow* window, FlValue* payload);
void mvd_gnome_command(GtkWindow* window, const char* method, FlValue* payload,
    std::function<void(FlValue*, const char*)> done);
#endif
