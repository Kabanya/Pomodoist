#ifndef MVD_LINUX_INTERNAL_H_
#define MVD_LINUX_INTERNAL_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <glib.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  int64_t token;
  double width;
  double height;
  const char* title;
  const char* title_bar_style;
  gboolean window_button_visibility;
  gboolean focus_on_show;
  gboolean is_utility;
  gboolean linux_desktop_overlay;
  const char* linux_desktop_overlay_role;
  gboolean has_background_color;
  GdkRGBA background_color;
  gboolean has_position;
  double pos_x;
  double pos_y;
} MvdCreateWindowRequest;

typedef void (*MvdWindowCreatedCallback)(const MvdCreateWindowRequest* request);

gboolean mvd_linux_pomo_available(void);
void mvd_linux_prepare_pomo_window(GtkWindow* window);
gboolean mvd_linux_move_layer_window(GtkWindow* window, double x, double y,
                                    const char* display_id);
FlValue* mvd_linux_layer_bounds(GtkWindow* window);
gboolean mvd_linux_layer_output_lost(GtkWindow* window);

void mvd_linux_set_window_created_callback(MvdWindowCreatedCallback callback);

void mvd_linux_register_primary(GtkWindow* window, FlView* view);

void mvd_linux_complete_secondary_window(GtkWindow* window,
                                         FlView* view,
                                         int64_t token);
void mvd_linux_secondary_window_failed(int64_t token);
GtkWindow* mvd_linux_pomo_companion_window(void);

void mvd_linux_detach_flutter_quit_on_window_close(GtkWindow* window,
                                                   FlView* view);

#ifdef __cplusplus
}
#endif

#endif  // MVD_LINUX_INTERNAL_H_
