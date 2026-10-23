#ifndef MVD_LINUX_POMO_DRAG_H_
#define MVD_LINUX_POMO_DRAG_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Native Wayland placement uses the measured usable-relative extent.
gboolean mvd_linux_pomo_workarea(GdkMonitor* monitor, GdkRectangle* work);

// Only utility windows invoke these through the existing validated Pomo channel.
gboolean mvd_linux_pomo_drag_begin(GtkWindow* window, double x, double y,
    gboolean allow_cross_display, GdkMonitor* initial_monitor);
FlValue* mvd_linux_pomo_drag_position(GtkWindow* window);
void mvd_linux_pomo_drag_end(GtkWindow* window);

#endif  // MVD_LINUX_POMO_DRAG_H_
