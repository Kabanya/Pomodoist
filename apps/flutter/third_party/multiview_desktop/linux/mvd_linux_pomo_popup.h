#ifndef MVD_LINUX_POMO_POPUP_H_
#define MVD_LINUX_POMO_POPUP_H_
#include <gtk/gtk.h>

// A GTK popup child of the visible companion layer, with no independent role.
GtkWindow* mvd_linux_pomo_popup_new(GtkWindow* parent);
gboolean mvd_linux_pomo_popup_is(GtkWindow* window);
void mvd_linux_pomo_popup_move(GtkWindow* window,
    const GdkRectangle* parent_bounds, const GdkRectangle* desired_bounds);
gboolean mvd_linux_pomo_popup_show(GtkWindow* window, const GdkEvent* trigger);
void mvd_linux_pomo_popup_hide(GtkWindow* window);
gboolean mvd_linux_pomo_popup_bounds(GtkWindow* window, GdkRectangle* bounds);
// Observe explicit input before descendants consume it; the event is borrowed
// for this callback only. Installation is idempotent and never claims input.
typedef void (*MvdPomoPopupTriggerObserver)(GtkWindow*, const GdkEvent*, gpointer);
void mvd_linux_pomo_popup_watch(GtkWindow* window,
    MvdPomoPopupTriggerObserver observer, gpointer data);
#endif
