#include "mvd_linux_pomo_drag.h"
#include "mvd_linux_pomo_drag_state.h"
#include "mvd_linux_pomo_geometry.h"
#include <gtk-layer-shell.h>

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#include <wayland-client.h>
#include "protocols/relative-pointer-unstable-v1-client-protocol.h"
#endif
#include <cstring>
#include <memory>

namespace {
constexpr char kDragSession[] = "mvd-pomo-drag-session";

struct DragSession {
  mvd::PomoDragState state;
  GtkWindow* window = nullptr;  // Window owns the session; never retain it cyclically.
  GdkDevice* pointer = nullptr;  // Own only a GObject reference, never wl_pointer.
  GdkMonitor* initial_monitor = nullptr;
  bool allow_cross_display = true;
  bool wayland = false;
  guint tick_id = 0;
  int last_x = 0, last_y = 0;
#ifdef GDK_WINDOWING_WAYLAND
  zwp_relative_pointer_manager_v1* manager = nullptr;
  zwp_relative_pointer_v1* relative = nullptr;
#endif
  void Stop() {
    state.End();
    if (tick_id) {
      const guint id = tick_id;
      tick_id = 0;
      gtk_widget_remove_tick_callback(GTK_WIDGET(window), id);
    }
  }
  ~DragSession() {
    Stop();
#ifdef GDK_WINDOWING_WAYLAND
    if (relative) zwp_relative_pointer_v1_destroy(relative);
    if (manager) zwp_relative_pointer_manager_v1_destroy(manager);
#endif
    g_clear_object(&initial_monitor);
    g_clear_object(&pointer);
  }
};
using DragSessionHolder = std::shared_ptr<DragSession>;

void SampleX11(DragSession* session) {
#ifdef GDK_WINDOWING_X11
  if (!session->wayland) {
    int px = 0, py = 0;
    gdk_device_get_position(session->pointer, nullptr, &px, &py);
    session->state.SampleAbsolute(px, py);
  }
#else
  (void)session;
#endif
}

bool MonitorConnected(GdkDisplay* display, GdkMonitor* monitor) {
  if (!display || !monitor) return false;
  for (int i = 0; i < gdk_display_get_n_monitors(display); ++i) {
    if (gdk_display_get_monitor(display, i) == monitor) return true;
  }
  return false;
}

// GtkWidget requests these updates from its GDK frame clock at the output's
// refresh rate. Dart polls only bookkeeping; it never gates visual movement.
gboolean DragTick(GtkWidget* widget, GdkFrameClock*, gpointer data) {
  // A native operation could synchronously hide/destroy the widget. Keep this
  // callback's session alive even if lifecycle cleanup removes the tick/data.
  const auto session = *static_cast<DragSessionHolder*>(data);
  SampleX11(session.get());
  double x = 0, y = 0;
  if (!session->state.Position(&x, &y)) {
    session->tick_id = 0;
    return G_SOURCE_REMOVE;
  }
  int width = 0, height = 0;
  gtk_window_get_size(GTK_WINDOW(widget), &width, &height);
  GdkMonitor* monitor = session->initial_monitor;
  if (!session->wayland && session->allow_cross_display) {
    monitor = gdk_display_get_monitor_at_point(gtk_widget_get_display(widget),
        static_cast<int>(std::round(x + width / 2.0)),
        static_cast<int>(std::round(y + height / 2.0)));
  }
  if (!MonitorConnected(gtk_widget_get_display(widget), monitor)) {
    mvd_linux_pomo_drag_end(GTK_WINDOW(widget));
    return G_SOURCE_REMOVE;
  }
  GdkRectangle work{};
  if (!mvd_linux_pomo_workarea(monitor, &work)) return G_SOURCE_CONTINUE;
  const auto visual = mvd::ClampPomoDragPosition(work.x, work.y,
      work.width, work.height, width, height, x, y);
  const int next_x = static_cast<int>(std::round(visual.x));
  const int next_y = static_cast<int>(std::round(visual.y));
  if (next_x == session->last_x && next_y == session->last_y) return G_SOURCE_CONTINUE;
  session->last_x = next_x;
  session->last_y = next_y;
  if (session->wayland) {
    // NEVER change the layer monitor during an implicit pointer grab: GTK layer
    // reassignment hides/remaps the surface and drops that grab. Dart uses the
    // raw sampler position for a destination handoff only after dragEnd.
    const auto margins = mvd::LayerPlacement(work.x, work.y, next_x, next_y);
    gtk_layer_set_margin(session->window, GTK_LAYER_SHELL_EDGE_LEFT, margins.left);
    gtk_layer_set_margin(session->window, GTK_LAYER_SHELL_EDGE_TOP, margins.top);
  } else {
    gtk_window_move(session->window, next_x, next_y);
  }
  return G_SOURCE_CONTINUE;
}

#ifdef GDK_WINDOWING_WAYLAND
void RegistryGlobal(void* data, wl_registry* registry, uint32_t name,
                    const char* interface, uint32_t version) {
  auto* session = static_cast<DragSession*>(data);
  if (!session->manager && version >= 1 &&
      std::strcmp(interface, zwp_relative_pointer_manager_v1_interface.name) == 0) {
    session->manager = static_cast<zwp_relative_pointer_manager_v1*>(
        wl_registry_bind(registry, name, &zwp_relative_pointer_manager_v1_interface, 1));
  }
}
void RegistryRemoved(void*, wl_registry*, uint32_t) {}
const wl_registry_listener kRegistryListener{RegistryGlobal, RegistryRemoved};

void RelativeMotion(void* data, zwp_relative_pointer_v1*, uint32_t, uint32_t,
                    wl_fixed_t dx, wl_fixed_t dy, wl_fixed_t, wl_fixed_t) {
  // Accelerated dx/dy share wl_pointer's logical coordinate units. Unaccelerated
  // deltas would ignore the user's acceleration settings. Surface relocation can
  // emit absolute motion, but cannot add physical relative motion here.
  static_cast<DragSession*>(data)->state.AddRelative(
      wl_fixed_to_double(dx), wl_fixed_to_double(dy));
}
const zwp_relative_pointer_v1_listener kRelativeListener{RelativeMotion};

bool BeginWayland(DragSession* session, GdkDisplay* gdk_display) {
  wl_display* display = gdk_wayland_display_get_wl_display(gdk_display);
  wl_pointer* pointer = gdk_wayland_device_get_wl_pointer(session->pointer);
  if (!display || !pointer) return false;
  // Discovery dispatches only our private registry queue. Never disconnect,
  // destroy, read independently from, or replace GDK's display/pointer listener.
  wl_event_queue* queue = wl_display_create_queue(display);
  if (!queue) return false;
  wl_registry* registry = wl_display_get_registry(display);
  if (!registry) {
    wl_event_queue_destroy(queue);
    return false;
  }
  wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(registry), queue);
  wl_registry_add_listener(registry, &kRegistryListener, session);
  const bool discovered = wl_display_roundtrip_queue(display, queue) >= 0;
  wl_registry_destroy(registry);
  if (session->manager) {
    // GTK3 dispatches the default display queue from its existing GLib source.
    wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(session->manager), nullptr);
  }
  wl_event_queue_destroy(queue);
  if (!discovered || !session->manager) return false;
  session->relative = zwp_relative_pointer_manager_v1_get_relative_pointer(
      session->manager, pointer);
  if (!session->relative) return false;
  zwp_relative_pointer_v1_add_listener(session->relative, &kRelativeListener, session);
  wl_display_flush(display);
  return true;
}
#endif

void EndOnLifecycle(GtkWidget* widget, gpointer) {
  mvd_linux_pomo_drag_end(GTK_WINDOW(widget));
}
}  // namespace

gboolean mvd_linux_pomo_drag_begin(GtkWindow* window, double x, double y,
    gboolean allow_cross_display, GdkMonitor* initial_monitor) {
  if (!window || !gtk_widget_get_mapped(GTK_WIDGET(window))) return FALSE;
  mvd_linux_pomo_drag_end(window);
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  GdkSeat* seat = display ? gdk_display_get_default_seat(display) : nullptr;
  GdkDevice* pointer = seat ? gdk_seat_get_pointer(seat) : nullptr;
  if (!pointer) return FALSE;
  auto session = std::make_shared<DragSession>();
  session->window = window;
  session->allow_cross_display = allow_cross_display;
  session->last_x = static_cast<int>(std::round(x));
  session->last_y = static_cast<int>(std::round(y));
  session->pointer = GDK_DEVICE(g_object_ref(pointer));
  if (gtk_layer_is_layer_window(window) && gtk_layer_get_monitor(window)) {
    initial_monitor = gtk_layer_get_monitor(window);
  }
  if (!initial_monitor) {
    GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
    if (gdk_window) initial_monitor = gdk_display_get_monitor_at_window(display, gdk_window);
  }
  if (!MonitorConnected(display, initial_monitor)) return FALSE;
  session->initial_monitor = GDK_MONITOR(g_object_ref(initial_monitor));
  bool available = false;
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_DISPLAY(display)) {
    int px = 0, py = 0;
    gdk_device_get_position(pointer, nullptr, &px, &py);
    available = session->state.BeginAbsolute(x, y, px, py);
  }
#endif
#ifdef GDK_WINDOWING_WAYLAND
  if (GDK_IS_WAYLAND_DISPLAY(display)) {
    session->wayland = true;
    available = session->state.BeginRelative(x, y) && BeginWayland(session.get(), display);
  }
#endif
  if (!available) return FALSE;
  g_object_set_data_full(G_OBJECT(window), kDragSession, new DragSessionHolder(session),
      +[](gpointer value) {
        auto* holder = static_cast<DragSessionHolder*>(value);
        (*holder)->Stop();
        delete holder;
      });
  session->tick_id = gtk_widget_add_tick_callback(GTK_WIDGET(window), DragTick,
      new DragSessionHolder(session),
      +[](gpointer value) { delete static_cast<DragSessionHolder*>(value); });
  if (!g_object_get_data(G_OBJECT(window), "mvd-pomo-drag-hooks")) {
    g_signal_connect(window, "hide", G_CALLBACK(EndOnLifecycle), nullptr);
    g_signal_connect(window, "destroy", G_CALLBACK(EndOnLifecycle), nullptr);
    g_object_set_data(G_OBJECT(window), "mvd-pomo-drag-hooks", GINT_TO_POINTER(1));
  }
  return TRUE;
}

FlValue* mvd_linux_pomo_drag_position(GtkWindow* window) {
  auto* holder = window ? static_cast<DragSessionHolder*>(
      g_object_get_data(G_OBJECT(window), kDragSession)) : nullptr;
  if (!holder) return nullptr;
  const auto session = *holder;
  SampleX11(session.get());
  double x = 0, y = 0;
  if (!session->state.Position(&x, &y)) return nullptr;
  FlValue* result = fl_value_new_map();
  fl_value_set_string_take(result, "x", fl_value_new_float(x));
  fl_value_set_string_take(result, "y", fl_value_new_float(y));
  return result;
}

void mvd_linux_pomo_drag_end(GtkWindow* window) {
  if (window) g_object_set_data(G_OBJECT(window), kDragSession, nullptr);
}
