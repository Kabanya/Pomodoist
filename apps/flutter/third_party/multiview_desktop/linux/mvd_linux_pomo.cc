#include <multiview_desktop/multiview_desktop_runner.h>

#include "mvd_linux_internal.h"
#include "mvd_linux_pomo_geometry.h"
#include "mvd_linux_pomo_drag.h"
#include "mvd_linux_pomo_identity.h"
#include "mvd_linux_window.h"
#include <gtk-layer-shell.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif
#include <cmath>
#include <limits>
#include <set>
#include <string>

namespace {
const char* Backend() {
  GdkDisplay* display = gdk_display_get_default();
#ifdef GDK_WINDOWING_X11
  if (display && GDK_IS_X11_DISPLAY(display)) return "x11";
#endif
#ifdef GDK_WINDOWING_WAYLAND
  if (display && GDK_IS_WAYLAND_DISPLAY(display)) return "wayland";
#endif
  return "unknown";
}
const char* UnavailableReason() {
  if (!gdk_display_get_default() ||
      gdk_display_get_n_monitors(gdk_display_get_default()) == 0) return "displayUnavailable";
  if (g_str_equal(Backend(), "x11")) {
    GdkScreen* screen = gdk_screen_get_default();
    return screen && gdk_screen_is_composited(screen) &&
        gdk_screen_get_rgba_visual(screen) ? nullptr : "compositorUnavailable";
  }
  if (g_str_equal(Backend(), "wayland")) {
    if (!gtk_layer_is_supported()) return "layerShellUnavailable";
    if (gtk_layer_get_protocol_version() < 4) return "layerShellOnDemandUnavailable";
    return nullptr;
  }
  return "backendUnsupported";
}
std::string MonitorId(GdkMonitor* monitor) {
  auto* cached = static_cast<const char*>(g_object_get_data(G_OBJECT(monitor), "mvd-display-id"));
  if (cached) return cached;
  // Model/manufacturer/physical dimensions survive enumeration order changes.
  // GTK3 has no portable connector-name API. Identical displays receive a
  // connection-lifetime suffix, stored on GdkMonitor rather than list position.
  const char* model = gdk_monitor_get_model(monitor);
  const char* maker = gdk_monitor_get_manufacturer(monitor);
  g_autofree gchar* base = g_strdup_printf("%s:%s:%dx%d", maker ? maker : "",
      model ? model : "display", gdk_monitor_get_width_mm(monitor),
      gdk_monitor_get_height_mm(monitor));
  std::set<std::string> allocated;
  GdkDisplay* display = gdk_monitor_get_display(monitor);
  for (int i = 0; i < gdk_display_get_n_monitors(display); ++i) {
    GdkMonitor* peer = gdk_display_get_monitor(display, i);
    auto* peer_id = static_cast<const char*>(g_object_get_data(G_OBJECT(peer), "mvd-display-id"));
    if (peer != monitor && peer_id) allocated.insert(peer_id);
  }
  const std::string id = mvd::AvailableMonitorId(base, allocated);
  g_object_set_data_full(G_OBJECT(monitor), "mvd-display-id", g_strdup(id.c_str()), g_free);
  return id;
}
GdkMonitor* MonitorById(const char* id, double x, double y) {
  GdkDisplay* display = gdk_display_get_default();
  if (!display) return nullptr;
  for (int i = 0; i < gdk_display_get_n_monitors(display); ++i) {
    GdkMonitor* monitor = gdk_display_get_monitor(display, i);
    if (id && MonitorId(monitor) == id) return monitor;
  }
  // A stale explicit display is rejected instead of jumping to an unrelated one.
  if (id && *id) return nullptr;
  return gdk_display_get_monitor_at_point(display, static_cast<int>(x), static_cast<int>(y));
}
void Number(FlValue* map, const char* key, double value) {
  fl_value_set_string_take(map, key, fl_value_new_float(value));
}
void String(FlValue* map, const char* key, const char* value) {
  fl_value_set_string_take(map, key, fl_value_new_string(value ? value : ""));
}
FlValue* Environment() {
  FlValue* result = fl_value_new_map();
  const char* reason = UnavailableReason();
  fl_value_set_string_take(result, "available", fl_value_new_bool(reason == nullptr));
  String(result, "backend", Backend());
  String(result, "desktop", g_getenv("XDG_CURRENT_DESKTOP"));
  String(result, "sessionType", g_getenv("XDG_SESSION_TYPE"));
  g_autofree gchar* distribution = g_get_os_info(G_OS_INFO_KEY_ID);
  String(result, "distribution", distribution);
  String(result, "followSource", reason ? "none" : g_str_equal(Backend(), "x11") ? "cursor" : "workspace");
  if (reason) String(result, "reason", reason);
  FlValue* monitors = fl_value_new_list();
  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* primary = display ? gdk_display_get_primary_monitor(display) : nullptr;
  if (!primary && display && gdk_display_get_n_monitors(display) > 0)
    primary = gdk_display_get_monitor(display, 0);
  String(result, "primaryDisplayId", primary ? MonitorId(primary).c_str() : "");
  if (display) {
    for (int i = 0; i < gdk_display_get_n_monitors(display); ++i) {
      GdkMonitor* monitor = gdk_display_get_monitor(display, i);
      GdkRectangle geometry{}, work{};
      gdk_monitor_get_geometry(monitor, &geometry);
      gdk_monitor_get_workarea(monitor, &work);
      FlValue* entry = fl_value_new_map();
      String(entry, "id", MonitorId(monitor).c_str());
      String(entry, "name", gdk_monitor_get_model(monitor));
      Number(entry, "x", geometry.x); Number(entry, "y", geometry.y);
      Number(entry, "width", geometry.width); Number(entry, "height", geometry.height);
      Number(entry, "workX", work.x); Number(entry, "workY", work.y);
      Number(entry, "workWidth", work.width); Number(entry, "workHeight", work.height);
      Number(entry, "scale", gdk_monitor_get_scale_factor(monitor));
      fl_value_append_take(monitors, entry);
    }
  }
  fl_value_set_string_take(result, "displays", monitors);
  return result;
}
bool Numeric(FlValue* map, const char* key, double* result) {
  FlValue* value = map ? fl_value_lookup_string(map, key) : nullptr;
  if (!value) return false;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) *result = fl_value_get_float(value);
  else if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) *result = fl_value_get_int(value);
  else return false;
  // Coordinates reach GTK's integer API; reject values which overflow casts.
  return std::isfinite(*result) && std::abs(*result) < std::numeric_limits<int>::max() / 4;
}
bool Boolean(FlValue* map, const char* key) {
  FlValue* value = fl_value_lookup_string(map, key);
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(value);
}
void ApplyInput(GtkWidget* widget, cairo_region_t* region) {
  GdkWindow* window = gtk_widget_get_window(widget);
  if (window) {
    gdk_window_input_shape_combine_region(window, region, 0, 0);
    gdk_window_set_opaque_region(window, nullptr);
  }
  if (GTK_IS_CONTAINER(widget)) gtk_container_forall(GTK_CONTAINER(widget),
      [](GtkWidget* child, gpointer data) { ApplyInput(child, static_cast<cairo_region_t*>(data)); }, region);
}
FlMethodResponse* OkResponse(FlValue* result = nullptr) {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}
FlMethodResponse* Error(const char* code, const char* message) {
  return FL_METHOD_RESPONSE(fl_method_error_response_new(code, message, nullptr));
}
}  // namespace

gboolean mvd_linux_pomo_available(void) { return UnavailableReason() == nullptr; }

void mvd_linux_prepare_pomo_window(GtkWindow* window) {
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_skip_pager_hint(window, TRUE);
  gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_UTILITY);
  gtk_window_set_keep_above(window, TRUE);
  // Accept keyboard after a click, without requesting focus when mapped.
  gtk_window_set_accept_focus(window, TRUE);
  gtk_window_set_focus_on_map(window, FALSE);
  GdkVisual* visual = gdk_screen_get_rgba_visual(gtk_window_get_screen(window));
  if (visual) gtk_widget_set_visual(GTK_WIDGET(window), visual);
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  GtkCssProvider* provider = gtk_css_provider_new();
  gtk_css_provider_load_from_data(provider,
      "window, window.background {background:transparent;box-shadow:none;border:0;border-radius:0;}", -1, nullptr);
  gtk_style_context_add_provider(gtk_widget_get_style_context(GTK_WIDGET(window)),
      GTK_STYLE_PROVIDER(provider), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
  g_object_unref(provider);
  if (g_str_equal(Backend(), "wayland") && !UnavailableReason()) {
    // This MUST run before gtk_widget_realize (including realization via FlView).
    gtk_layer_init_for_window(window);
    gtk_layer_set_namespace(window, "pomodoist-pomo");
    gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_TOP);
    gtk_layer_set_exclusive_zone(window, 0);
    gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
  }
}

gboolean mvd_linux_move_layer_window(GtkWindow* window, double x, double y, const char* display_id) {
  GdkMonitor* monitor = MonitorById(display_id, x, y);
  if (!monitor || !gtk_layer_is_layer_window(window)) return FALSE;
  GdkRectangle work{};
  gdk_monitor_get_workarea(monitor, &work);
  const auto margins = mvd::LayerPlacement(work.x, work.y, x, y);
  // Avoid remapping on every drag update: changing monitor remaps the surface.
  if (gtk_layer_get_monitor(window) != monitor) gtk_layer_set_monitor(window, monitor);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_LEFT, margins.left);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_TOP, margins.top);
  return TRUE;
}

gboolean mvd_linux_layer_output_lost(GtkWindow* window) {
  if (!gtk_layer_is_layer_window(window)) return FALSE;
  GdkMonitor* monitor = gtk_layer_get_monitor(window);
  if (!monitor) return FALSE;
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  for (int i = 0; i < gdk_display_get_n_monitors(display); ++i) {
    if (gdk_display_get_monitor(display, i) == monitor) return FALSE;
  }
  return TRUE;
}

FlValue* mvd_linux_layer_bounds(GtkWindow* window) {
  GdkMonitor* monitor = gtk_layer_get_monitor(window);
  if (!monitor) {
    GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
    GdkWindow* gdk = gtk_widget_get_window(GTK_WIDGET(window));
    if (gdk) monitor = gdk_display_get_monitor_at_window(display, gdk);
    if (!monitor) monitor = gdk_display_get_primary_monitor(display);
    if (!monitor && gdk_display_get_n_monitors(display)) monitor = gdk_display_get_monitor(display, 0);
  }
  GdkRectangle work{};
  if (monitor) gdk_monitor_get_workarea(monitor, &work);
  int width = 0, height = 0;
  gtk_window_get_size(window, &width, &height);
  FlValue* bounds = fl_value_new_map();
  Number(bounds, "x", work.x + gtk_layer_get_margin(window, GTK_LAYER_SHELL_EDGE_LEFT));
  Number(bounds, "y", work.y + gtk_layer_get_margin(window, GTK_LAYER_SHELL_EDGE_TOP));
  Number(bounds, "width", width); Number(bounds, "height", height);
  Number(bounds, "scale", gtk_widget_get_scale_factor(GTK_WIDGET(window)));
  if (monitor) String(bounds, "displayId", MonitorId(monitor).c_str());
  return bounds;
}

extern "C" {
GtkWindow* multiview_desktop_linux_get_window(int64_t view_id) {
  auto window = MvdLinuxWindow::Find(view_id);
  return window ? window->window : nullptr;
}
FlView* multiview_desktop_linux_get_view(int64_t view_id) {
  auto window = MvdLinuxWindow::Find(view_id);
  return window ? window->view : nullptr;
}
FlMethodResponse* multiview_desktop_linux_pomo_method(const char* method, FlValue* arguments) {
  if (g_str_equal(method, "environment")) {
    g_autoptr(FlValue) value = Environment();
    return OkResponse(value);
  }
  if (g_str_equal(method, "cursor")) {
    if (!g_str_equal(Backend(), "x11")) return OkResponse();
    GdkDisplay* display = gdk_display_get_default();
    GdkSeat* seat = display ? gdk_display_get_default_seat(display) : nullptr;
    GdkDevice* pointer = seat ? gdk_seat_get_pointer(seat) : nullptr;
    if (!pointer) return OkResponse();
    int x = 0, y = 0;
    gdk_device_get_position(pointer, nullptr, &x, &y);
    g_autoptr(FlValue) value = fl_value_new_map();
    Number(value, "x", x); Number(value, "y", y);
    return OkResponse(value);
  }
  if (!arguments || fl_value_get_type(arguments) != FL_VALUE_TYPE_MAP)
    return Error("arguments", "Missing Pomo arguments");
  FlValue* id = fl_value_lookup_string(arguments, "viewId");
  if (!id || fl_value_get_type(id) != FL_VALUE_TYPE_INT)
    return Error("arguments", "Invalid Pomo view");
  auto wm = MvdLinuxWindow::Find(fl_value_get_int(id));
  if (!wm || !wm->window || !wm->view) return Error("window", "Pomo window unavailable");
  if (!wm->is_pomo) return Error("window", "Pomo operations require a Pomo utility window");
  GtkWindow* window = wm->window;
  if (g_str_equal(method, "dragBegin")) {
    g_autoptr(FlValue) bounds = wm->GetBounds();
    double x = 0, y = 0;
    const char* display_id = nullptr;
    FlValue* encoded_display = fl_value_lookup_string(arguments, "displayId");
    if (encoded_display && fl_value_get_type(encoded_display) == FL_VALUE_TYPE_STRING)
      display_id = fl_value_get_string(encoded_display);
    FlValue* encoded_cross = fl_value_lookup_string(arguments, "allowCrossDisplayDrag");
    const bool allow_cross = !encoded_cross ||
        (fl_value_get_type(encoded_cross) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(encoded_cross));
    const bool has_origin = bounds && Numeric(bounds, "x", &x) && Numeric(bounds, "y", &y);
    GdkMonitor* monitor = has_origin ? MonitorById(display_id, x, y) : nullptr;
    const bool available = has_origin && monitor &&
        mvd_linux_pomo_drag_begin(window, x, y, allow_cross, monitor);
    g_autoptr(FlValue) result = fl_value_new_bool(available);
    return OkResponse(result);
  }
  if (g_str_equal(method, "dragPosition")) {
    g_autoptr(FlValue) result = mvd_linux_pomo_drag_position(window);
    return OkResponse(result);
  }
  if (g_str_equal(method, "dragEnd")) {
    mvd_linux_pomo_drag_end(window);
    return OkResponse();
  }
  if (g_str_equal(method, "detach")) {
    mvd_linux_pomo_drag_end(window);
    ApplyInput(GTK_WIDGET(window), nullptr);
    g_object_set_data(G_OBJECT(window), "mvd-pomo-region", nullptr);
    return OkResponse();
  }
  if (g_str_equal(method, "bounds")) {
    g_autoptr(FlValue) value = wm->GetBounds();
    if (value && !gtk_layer_is_layer_window(window))
      Number(value, "scale", gtk_widget_get_scale_factor(GTK_WIDGET(window)));
    return OkResponse(value);
  }
  if (g_str_equal(method, "move")) {
    double x, y;
    if (!Numeric(arguments, "x", &x) || !Numeric(arguments, "y", &y))
      return Error("arguments", "Invalid logical display position");
    const char* display_id = nullptr;
    FlValue* encoded = fl_value_lookup_string(arguments, "displayId");
    if (encoded && fl_value_get_type(encoded) == FL_VALUE_TYPE_STRING)
      display_id = fl_value_get_string(encoded);
    if (display_id && *display_id && !MonitorById(display_id, x, y))
      return Error("display", "Pomo display unavailable");
    if (gtk_layer_is_layer_window(window)) {
      if (!mvd_linux_move_layer_window(window, x, y, display_id))
        return Error("display", "Pomo display unavailable");
    } else wm->SetPosition(x, y);
    return OkResponse();
  }
  if (!g_str_equal(method, "configure"))
    return FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  FlValue* regions = fl_value_lookup_string(arguments, "regions");
  if (!regions || fl_value_get_type(regions) != FL_VALUE_TYPE_LIST)
    return Error("arguments", "Missing Pomo input regions");
  cairo_region_t* combined = cairo_region_create();
  for (size_t i = 0; i < fl_value_get_length(regions); ++i) {
    FlValue* entry = fl_value_get_list_value(regions, i);
    double x, y, width, height;
    if (fl_value_get_type(entry) != FL_VALUE_TYPE_MAP ||
        !Numeric(entry, "x", &x) || !Numeric(entry, "y", &y) ||
        !Numeric(entry, "width", &width) || !Numeric(entry, "height", &height) ||
        width < 0 || height < 0 || width > 32768 || height > 32768) {
      cairo_region_destroy(combined);
      return Error("arguments", "Invalid Pomo input region");
    }
    for (const auto& r : mvd::InputRectangles({x, y, width, height,
            Boolean(entry, "rectangle"), Boolean(entry, "rounded")})) {
      const cairo_rectangle_int_t rect{r.x, r.y, r.width, r.height};
      cairo_region_union_rectangle(combined, &rect);
    }
  }
  // Reapplying regions must not recreate the surface, move it, or take focus.
  g_object_set_data_full(G_OBJECT(window), "mvd-pomo-region", combined,
      reinterpret_cast<GDestroyNotify>(cairo_region_destroy));
  ApplyInput(GTK_WIDGET(window), combined);
  if (!g_object_get_data(G_OBJECT(window), "mvd-pomo-map-hook")) {
    g_signal_connect(window, "map", G_CALLBACK(+[](GtkWidget* widget, gpointer) {
      auto* region = static_cast<cairo_region_t*>(g_object_get_data(G_OBJECT(widget), "mvd-pomo-region"));
      if (region) ApplyInput(widget, region);
    }), nullptr);
    g_object_set_data(G_OBJECT(window), "mvd-pomo-map-hook", GINT_TO_POINTER(1));
  }
  return OkResponse();
}
}  // extern "C"
