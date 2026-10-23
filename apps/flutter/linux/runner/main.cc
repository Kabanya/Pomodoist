#include "my_application.h"
#include "../../third_party/multiview_desktop/linux/mvd_linux_gnome_policy.h"
#include <X11/Xlib.h>

int main(int argc, char** argv) {
  // GNOME can expose utility window roles reliably through XWayland. Select
  // the process-wide GDK backend before GtkApplication initializes GTK.
  if (mvd::GnomeWayland(g_getenv("XDG_CURRENT_DESKTOP"), g_getenv("XDG_SESSION_TYPE"))) {
    Display* probe = XOpenDisplay(nullptr);
    const auto backend = mvd::GnomeStartupBackend(g_getenv("XDG_CURRENT_DESKTOP"),
        g_getenv("XDG_SESSION_TYPE"), probe != nullptr);
    if (probe) XCloseDisplay(probe);
    if (backend == mvd::StartupBackend::x11) {
      g_setenv("GDK_BACKEND", "x11", TRUE);
      gdk_set_allowed_backends("x11");
    } else {
      g_setenv("GDK_BACKEND", "wayland", TRUE);
      gdk_set_allowed_backends("wayland");
      g_setenv("POMODOIST_GNOME_XWAYLAND_UNAVAILABLE", "1", TRUE);
    }
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
