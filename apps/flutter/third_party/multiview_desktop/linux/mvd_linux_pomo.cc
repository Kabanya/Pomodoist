#include <multiview_desktop/multiview_desktop_runner.h>

#include "mvd_linux_internal.h"
#include "mvd_linux_gnome.h"
#include "mvd_linux_pomo_geometry.h"
#include "mvd_linux_pomo_drag.h"
#include "mvd_linux_pomo_identity.h"
#include "mvd_linux_window.h"
#include "mvd_linux_pomo_popup.h"
#include <gtk-layer-shell.h>
#include "protocols/xdg-output-unstable-v1-client-protocol.h"
#include <wayland-client.h>
#include <cstring>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif
#include <cmath>
#include <limits>
#include <map>
#include <memory>
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
// Layer-shell exposes usable width/height through an all-anchored surface, but
// never its global origin. Keep full monitor coordinates for identity and cursor
// mapping; placement/bounds use usable-relative coordinates labeled by that origin.
struct LayerAreaProbe {
  explicit LayerAreaProbe(GdkMonitor* value) : monitor(GDK_MONITOR(g_object_ref(value))) {}
  ~LayerAreaProbe() {
    Retire();
    if (logical_output) zxdg_output_v1_destroy(logical_output);
    g_object_unref(monitor);
  }
  void Retire() {
    GtkWidget* old = window; window = nullptr;
    if (old) gtk_widget_destroy(old);
  }
  GdkMonitor* monitor;
  GtkWidget* window = nullptr;
  int width = 0, height = 0;
  bool ready = false;
  zxdg_output_v1* logical_output = nullptr;
  wl_output* borrowed_output = nullptr;
  mvd::LogicalOutputState logical;
};
std::map<GdkMonitor*, std::unique_ptr<LayerAreaProbe>> layer_areas;
std::set<GtkWindow*> layer_utilities;
int layer_area_requests = 0;

wl_registry* logical_registry = nullptr;
wl_callback* logical_registry_sync = nullptr;
zxdg_output_manager_v1* logical_manager = nullptr;
uint32_t logical_manager_name = 0;
bool logical_registry_done = false;

void AttachLogicalOutput(LayerAreaProbe* area) {
#ifdef GDK_WINDOWING_WAYLAND
  if (!logical_manager) return;
  wl_output* output = gdk_wayland_monitor_get_wl_output(area->monitor);
  if (area->logical_output && area->borrowed_output == output) return;
  if (area->logical_output) zxdg_output_v1_destroy(area->logical_output);
  area->logical_output = nullptr; area->borrowed_output = output;
  area->logical = mvd::LogicalOutputState{};
  if (!output) return;
  // A new xdg object has our listener. GDK's borrowed wl_output/display and their
  // listeners remain untouched; GTK dispatches our normal queue asynchronously.
  area->logical_output = zxdg_output_manager_v1_get_xdg_output(logical_manager, output);
  static const zxdg_output_v1_listener listener{
    +[](void* data, zxdg_output_v1*, int32_t x, int32_t y) {
      static_cast<LayerAreaProbe*>(data)->logical.Position(x, y);
    },
    +[](void* data, zxdg_output_v1*, int32_t width, int32_t height) {
      static_cast<LayerAreaProbe*>(data)->logical.Size(width, height);
    },
    +[](void* data, zxdg_output_v1*) { static_cast<LayerAreaProbe*>(data)->logical.Done(); },
    +[](void* data, zxdg_output_v1*, const char* name) {
      static_cast<LayerAreaProbe*>(data)->logical.Name(name);
    },
    +[](void*, zxdg_output_v1*, const char*) {},
  };
  zxdg_output_v1_add_listener(area->logical_output, &listener, area);
#endif
}
void EnsureLogicalOutputs() {
#ifdef GDK_WINDOWING_WAYLAND
  if (logical_registry) return;
  GdkDisplay* gdk = gdk_display_get_default();
  wl_display* display = gdk ? gdk_wayland_display_get_wl_display(gdk) : nullptr;
  if (!display) { logical_registry_done = true; return; }
  logical_registry = wl_display_get_registry(display);
  static const wl_registry_listener listener{
    +[](void*, wl_registry* registry, uint32_t name, const char* interface, uint32_t version) {
      if (logical_manager || version < 2 || std::strcmp(interface, zxdg_output_manager_v1_interface.name)) return;
      // Version2 has its own done event. Version3 instead relies on GDK-owned
      // wl_output.done, whose listener must never be replaced or intercepted.
      logical_manager = static_cast<zxdg_output_manager_v1*>(
          wl_registry_bind(registry, name, &zxdg_output_manager_v1_interface, 2));
      logical_manager_name = name;
      for (auto& entry : layer_areas) AttachLogicalOutput(entry.second.get());
    },
    +[](void*, wl_registry*, uint32_t name) {
      if (!logical_manager || name != logical_manager_name) return;
      for (auto& entry : layer_areas) {
        if (entry.second->logical_output) zxdg_output_v1_destroy(entry.second->logical_output);
        entry.second->logical_output = nullptr; entry.second->borrowed_output = nullptr;
        entry.second->logical = mvd::LogicalOutputState{};
      }
      zxdg_output_manager_v1_destroy(logical_manager); logical_manager = nullptr;
    },
  };
  wl_registry_add_listener(logical_registry, &listener, nullptr);
  logical_registry_sync = wl_display_sync(display);
  static const wl_callback_listener synced{+[](void*, wl_callback* callback, uint32_t) {
    logical_registry_done = true; logical_registry_sync = nullptr;
    wl_callback_destroy(callback);
  }};
  wl_callback_add_listener(logical_registry_sync, &synced, nullptr);
  wl_display_flush(display);
#else
  logical_registry_done = true;
#endif
}
bool HasLogicalOutput(GdkMonitor* monitor) {
  auto it = layer_areas.find(monitor);
  return logical_manager && it != layer_areas.end() && it->second->logical.Get().ready;
}
void MonitorGeometry(GdkMonitor* monitor, GdkRectangle* geometry) {
  if (HasLogicalOutput(monitor)) {
    const auto& logical = layer_areas.at(monitor)->logical.Get().geometry;
    *geometry = {logical.x, logical.y, logical.width, logical.height};
  } else {
    // Older compositors may not expose xdg-output v2. This is an explicit GDK
    // fallback, not a claim that GDK has authoritative live logical geometry.
    gdk_monitor_get_geometry(monitor, geometry);
  }
}
const char* MonitorName(GdkMonitor* monitor) {
  if (HasLogicalOutput(monitor)) {
    const auto& name = layer_areas.at(monitor)->logical.Get().name;
    if (!name.empty()) return name.c_str();
  }
  return gdk_monitor_get_model(monitor);
}

void RetireIdleLayerProbes() {
  if (!layer_utilities.empty() || layer_area_requests) return;
  for (auto& entry : layer_areas) entry.second->Retire();
}
bool MonitorConnected(GdkDisplay* display, GdkMonitor* monitor) {
  if (!display || !monitor) return false;
  for (int i = 0; i < gdk_display_get_n_monitors(display); ++i)
    if (gdk_display_get_monitor(display, i) == monitor) return true;
  return false;
}
void RecoverRemovedOutput(GdkDisplay* display, GdkMonitor* removed) {
  GdkMonitor* fallback = gdk_display_get_primary_monitor(display);
  if (!MonitorConnected(display, fallback)) fallback =
      gdk_display_get_n_monitors(display) ? gdk_display_get_monitor(display, 0) : nullptr;
  // A remap emits unmap/map and mutates layer_utilities. Retain a separate
  // snapshot while GTK closes popup children and releases the implicit grab.
  std::vector<GtkWindow*> affected;
  for (GtkWindow* window : layer_utilities) {
    if (gtk_layer_get_monitor(window) == removed)
      affected.push_back(GTK_WINDOW(g_object_ref(window)));
  }
  for (GtkWindow* window : affected) {
    // layer.closed queues gtk_window_close at default priority. A reassignment
    // can finish before that queued delete arrives, so monitor comparison alone
    // would misclassify it as manual dismissal. Consume only this dispatch turn;
    // a later explicit close must retain its ordinary lifecycle.
    g_object_set_data(G_OBJECT(window), "mvd-pomo-output-close", GINT_TO_POINTER(1));
    g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, +[](gpointer data) -> gboolean {
      g_object_set_data(G_OBJECT(data), "mvd-pomo-output-close", nullptr);
      return G_SOURCE_REMOVE;
    }, g_object_ref(window), g_object_unref);
    mvd_linux_pomo_drag_end(window);
    GdkRectangle work{};
    if (!fallback || !mvd_linux_pomo_workarea(fallback, &work)) {
      // No usable replacement yet: remove the raw GTK-layer monitor pointer
      // while hidden. Environment refresh will restore a retained companion.
      gtk_widget_hide(GTK_WIDGET(window));
      gtk_layer_set_monitor(window, fallback);
    } else {
      int width = 0, height = 0; gtk_window_get_size(window, &width, &height);
      const auto margins = mvd::ClampLayerMargins(work.width, work.height,
          width, height, {gtk_layer_get_margin(window, GTK_LAYER_SHELL_EDGE_LEFT),
              gtk_layer_get_margin(window, GTK_LAYER_SHELL_EDGE_TOP)});
      // GTK layer-shell 0.8 stores GdkMonitor as a borrowed raw pointer. Change
      // it before pruning the probe's owning ref; reassignment remaps the closed
      // layer instead of retaining a stale surface after compositor output loss.
      gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_LEFT, margins.left);
      gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_TOP, margins.top);
      gtk_layer_set_monitor(window, fallback);
    }
    g_object_unref(window);
  }
}
void PruneLayerAreas() {
  GdkDisplay* display = gdk_display_get_default();
  std::set<GdkMonitor*> connected;
  if (display) for (int i = 0; i < gdk_display_get_n_monitors(display); ++i)
    connected.insert(gdk_display_get_monitor(display, i));
  for (auto it = layer_areas.begin(); it != layer_areas.end();) {
    if (!connected.count(it->first)) it = layer_areas.erase(it);
    else ++it;
  }
}
void EnsureLayerAreas(bool refresh_idle_measurement = false) {
  PruneLayerAreas();
  EnsureLogicalOutputs();
  GdkDisplay* display = gdk_display_get_default();
  if (!display) return;
  if (!g_object_get_data(G_OBJECT(display), "mvd-pomo-area-watch")) {
    g_signal_connect(display, "monitor-removed", G_CALLBACK(+[](GdkDisplay* current, GdkMonitor* removed, gpointer) {
      RecoverRemovedOutput(current, removed);
      PruneLayerAreas();
    }), nullptr);
    g_object_set_data(G_OBJECT(display), "mvd-pomo-area-watch", GINT_TO_POINTER(1));
  }
  for (int i = 0; i < gdk_display_get_n_monitors(display); ++i) {
    GdkMonitor* monitor = gdk_display_get_monitor(display, i);
    auto& owned = layer_areas[monitor];
    if (!owned) owned = std::make_unique<LayerAreaProbe>(monitor);
    auto* probe = owned.get();
    AttachLogicalOutput(probe);
    if (probe->window) continue;
    // A fresh first-show query must observe a compositor configure, not a stale
    // extent retained while no utility was active.
    if (refresh_idle_measurement && layer_utilities.empty()) probe->ready = false;
    GtkWidget* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    probe->window = window;
    g_signal_connect(window, "destroy", G_CALLBACK(+[](GtkWidget*, gpointer data) {
      static_cast<LayerAreaProbe*>(data)->window = nullptr;
    }), probe);
    gtk_window_set_decorated(GTK_WINDOW(window), FALSE);
    gtk_window_set_accept_focus(GTK_WINDOW(window), FALSE);
    gtk_window_set_focus_on_map(GTK_WINDOW(window), FALSE);
    gtk_widget_set_app_paintable(window, TRUE);
    GdkVisual* visual = gdk_screen_get_rgba_visual(gtk_widget_get_screen(window));
    if (visual) gtk_widget_set_visual(window, visual);
    g_signal_connect(window, "draw", G_CALLBACK(+[](GtkWidget*, cairo_t* cr, gpointer) -> gboolean {
      cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
      cairo_set_source_rgba(cr, 0, 0, 0, 0); cairo_paint(cr); return TRUE;
    }), nullptr);
    // Store the shape on GtkWidget before realization. Setting only its GDK
    // window in realize is overwritten by GTK's later initial shape application.
    cairo_region_t* empty = cairo_region_create();
    gtk_widget_input_shape_combine_region(window, empty);
    cairo_region_destroy(empty);
    g_signal_connect(window, "realize", G_CALLBACK(+[](GtkWidget* widget, gpointer) {
      gdk_window_set_opaque_region(gtk_widget_get_window(widget), nullptr);
    }), nullptr);
    g_signal_connect(window, "configure-event", G_CALLBACK(+[](GtkWidget*, GdkEventConfigure* event, gpointer data) -> gboolean {
      auto* area = static_cast<LayerAreaProbe*>(data);
      // Configure may precede the logical-output done event. Keep its raw
      // extent and validate only when both independent streams are committed.
      area->width = event->width; area->height = event->height;
      area->ready = event->width > 0 && event->height > 0;
      return FALSE;
    }), probe);
    gtk_layer_init_for_window(GTK_WINDOW(window));
    gtk_layer_set_namespace(GTK_WINDOW(window), "pomodoist-workarea");
    gtk_layer_set_layer(GTK_WINDOW(window), GTK_LAYER_SHELL_LAYER_TOP);
    gtk_layer_set_exclusive_zone(GTK_WINDOW(window), 0);
    gtk_layer_set_keyboard_mode(GTK_WINDOW(window), GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
    gtk_layer_set_monitor(GTK_WINDOW(window), monitor);
    for (auto edge : {GTK_LAYER_SHELL_EDGE_LEFT, GTK_LAYER_SHELL_EDGE_RIGHT,
        GTK_LAYER_SHELL_EDGE_TOP, GTK_LAYER_SHELL_EDGE_BOTTOM})
      gtk_layer_set_anchor(GTK_WINDOW(window), edge, TRUE);
    gtk_widget_show(window);
  }
}
bool LayerAreasReady() {
  GdkDisplay* display = gdk_display_get_default();
  if (!display || !gdk_display_get_n_monitors(display) || !logical_registry_done) return false;
  for (int i = 0; i < gdk_display_get_n_monitors(display); ++i) {
    auto it = layer_areas.find(gdk_display_get_monitor(display, i));
    if (it == layer_areas.end() || !it->second->ready ||
        (logical_manager && !it->second->logical.Get().ready)) return false;
    GdkRectangle output{}; MonitorGeometry(it->first, &output);
    const auto work = mvd::MeasuredLayerWorkArea(output.x, output.y, output.width,
        output.height, it->second->width, it->second->height);
    if (work.width <= 0 || work.height <= 0) return false;
  }
  return true;
}
void ReleaseLayerUtility(GtkWindow* window) {
  layer_utilities.erase(window);
  RetireIdleLayerProbes();
}
const char* UnavailableReason() {
  if (mvd_gnome_context()) return mvd_gnome_available() ? nullptr : mvd_gnome_reason();
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
    if (!LayerAreasReady()) return "displayUnavailable";
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
  if (g_str_equal(Backend(), "wayland") && !mvd_gnome_context()) {
    for (int i = 0; i < gdk_display_get_n_monitors(display); ++i) {
      GdkMonitor* monitor = gdk_display_get_monitor(display, i);
      GdkRectangle geometry{}; MonitorGeometry(monitor, &geometry);
      if (x >= geometry.x && y >= geometry.y && x < geometry.x + geometry.width &&
          y < geometry.y + geometry.height) return monitor;
    }
    return gdk_display_get_primary_monitor(display);
  }
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
  String(result, "placementBackend", g_str_equal(Backend(), "x11") ? "x11" : "layerShell");
  String(result, "followSource", reason ? "none" : mvd_gnome_context() || g_str_equal(Backend(), "x11") ? "cursor" : "workspace");
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
      MonitorGeometry(monitor, &geometry);
      mvd_linux_pomo_workarea(monitor, &work);
      FlValue* entry = fl_value_new_map();
      String(entry, "id", MonitorId(monitor).c_str());
      String(entry, "name", MonitorName(monitor));
      if (!mvd_gnome_context() && g_str_equal(Backend(), "wayland"))
        String(entry, "geometrySource", HasLogicalOutput(monitor) ? "xdgOutputV2" : "gdkFallback");
      Number(entry, "x", geometry.x); Number(entry, "y", geometry.y);
      Number(entry, "width", geometry.width); Number(entry, "height", geometry.height);
      Number(entry, "workX", work.x); Number(entry, "workY", work.y);
      Number(entry, "workWidth", work.width); Number(entry, "workHeight", work.height);
      Number(entry, "scale", gdk_monitor_get_scale_factor(monitor));
      fl_value_append_take(monitors, entry);
    }
  }
  fl_value_set_string_take(result, "displays", monitors);
  if (mvd_gnome_context()) mvd_gnome_environment(result);
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
cairo_region_t* BuildInput(GtkWindow* window, FlValue* regions) {
  g_autoptr(FlValue) frame = mvd_gnome_window(window) ? mvd_gnome_bounds(window) : nullptr;
  double frame_width = 0, frame_height = 0;
  if (frame) { Numeric(frame, "width", &frame_width); Numeric(frame, "height", &frame_height); }
  GtkWidget* viewport = gtk_bin_get_child(GTK_BIN(window));
  if (!viewport) viewport = GTK_WIDGET(window);
  cairo_region_t* combined = cairo_region_create();
  for (size_t i = 0; i < fl_value_get_length(regions); ++i) {
    FlValue* entry = fl_value_get_list_value(regions, i);
    double x, y, width, height;
    if (fl_value_get_type(entry) != FL_VALUE_TYPE_MAP ||
        !Numeric(entry, "x", &x) || !Numeric(entry, "y", &y) ||
        !Numeric(entry, "width", &width) || !Numeric(entry, "height", &height) ||
        width < 0 || height < 0 || width > 32768 || height > 32768) {
      cairo_region_destroy(combined);
      return nullptr;
    }
    mvd::InputShape shape{x, y, width, height, Boolean(entry, "rectangle"), Boolean(entry, "rounded")};
    if (mvd_gnome_window(window)) shape = mvd::ViewportInputShape(shape, frame_width, frame_height,
        gtk_widget_get_allocated_width(viewport), gtk_widget_get_allocated_height(viewport));
    for (const auto& r : mvd::InputRectangles(shape)) {
      const cairo_rectangle_int_t rect{r.x, r.y, r.width, r.height};
      cairo_region_union_rectangle(combined, &rect);
    }
  }
  return combined;
}
void RefreshInput(GtkWindow* window) {
  auto* regions = static_cast<FlValue*>(g_object_get_data(G_OBJECT(window), "mvd-pomo-input-regions"));
  if (!regions) return;
  cairo_region_t* combined = BuildInput(window, regions);
  if (!combined) return;
  g_object_set_data_full(G_OBJECT(window), "mvd-pomo-region", combined,
      reinterpret_cast<GDestroyNotify>(cairo_region_destroy));
  ApplyInput(GTK_WIDGET(window), combined);
}
FlMethodResponse* OkResponse(FlValue* result = nullptr) {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}
FlMethodResponse* Error(const char* code, const char* message) {
  return FL_METHOD_RESPONSE(fl_method_error_response_new(code, message, nullptr));
}
}  // namespace

gboolean mvd_linux_pomo_workarea(GdkMonitor* monitor, GdkRectangle* work) {
  if (!monitor || !work) return FALSE;
  if (!MonitorConnected(gdk_display_get_default(), monitor)) {
    *work = {0, 0, 0, 0}; return FALSE;
  }
  if (mvd_gnome_context() || !g_str_equal(Backend(), "wayland")) {
    gdk_monitor_get_workarea(monitor, work); return TRUE;
  }
  GdkRectangle output{}; MonitorGeometry(monitor, &output);
  auto it = layer_areas.find(monitor);
  if (it == layer_areas.end() || !it->second->ready) { *work = {output.x, output.y, 0, 0}; return FALSE; }
  const auto area = mvd::MeasuredLayerWorkArea(output.x, output.y, output.width, output.height,
      it->second->width, it->second->height);
  *work = {area.x, area.y, area.width, area.height};
  return area.width > 0 && area.height > 0;
}

gboolean mvd_linux_pomo_available(void) { return UnavailableReason() == nullptr; }

void mvd_linux_prepare_pomo_window(GtkWindow* window) {
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_skip_pager_hint(window, TRUE);
  if (!mvd_linux_pomo_popup_is(window))
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
  if (!mvd_linux_pomo_popup_is(window) && !mvd_gnome_context() &&
      g_str_equal(Backend(), "wayland") && gtk_layer_is_supported() &&
      gtk_layer_get_protocol_version() >= 4) {
    // Hidden utility windows are reused. Map/unmap, not allocation alone, own
    // the shared probe lifetime; settings and companion can map independently.
    g_signal_connect(window, "map", G_CALLBACK(+[](GtkWidget* widget, gpointer) {
      layer_utilities.insert(GTK_WINDOW(widget)); EnsureLayerAreas();
    }), nullptr);
    g_signal_connect(window, "unmap", G_CALLBACK(+[](GtkWidget* widget, gpointer) {
      ReleaseLayerUtility(GTK_WINDOW(widget));
    }), nullptr);
    g_signal_connect(window, "destroy", G_CALLBACK(+[](GtkWidget* widget, gpointer) {
      ReleaseLayerUtility(GTK_WINDOW(widget));
    }), nullptr);
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
  if (!mvd_linux_pomo_workarea(monitor, &work)) return FALSE;
  const auto margins = mvd::LayerPlacement(work.x, work.y, x, y);
  // Avoid remapping on every drag update: changing monitor remaps the surface.
  if (gtk_layer_get_monitor(window) != monitor) gtk_layer_set_monitor(window, monitor);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_LEFT, margins.left);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_TOP, margins.top);
  return TRUE;
}

gboolean mvd_linux_layer_output_lost(GtkWindow* window) {
  if (g_object_get_data(G_OBJECT(window), "mvd-pomo-output-close")) {
    g_object_set_data(G_OBJECT(window), "mvd-pomo-output-close", nullptr);
    return TRUE;
  }
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
  if (!monitor || !mvd_linux_pomo_workarea(monitor, &work)) return nullptr;
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

namespace {
void Respond(FlMethodCall* call, FlValue* result, const char* error) {
  g_autoptr(FlMethodResponse) response = error ? Error("gnomeShell", error) : OkResponse(result);
  fl_method_call_respond(call, response, nullptr);
}
}  // namespace

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
    if (mvd_gnome_context()) {
      g_autoptr(FlValue) cursor = mvd_gnome_cursor(); return OkResponse(cursor);
    }
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
  if (g_str_equal(method, "setFollowing")) {
    mvd_gnome_following(arguments && Boolean(arguments, "enabled")); return OkResponse();
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
    ReleaseLayerUtility(window);
    ApplyInput(GTK_WIDGET(window), nullptr);
    g_object_set_data(G_OBJECT(window), "mvd-pomo-region", nullptr);
    g_object_set_data(G_OBJECT(window), "mvd-pomo-input-regions", nullptr);
    return OkResponse();
  }
  if (g_str_equal(method, "bounds")) {
    g_autoptr(FlValue) value = wm->GetBounds();
    if (value && !mvd_gnome_window(window) && !gtk_layer_is_layer_window(window))
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
  cairo_region_t* validated = BuildInput(window, regions);
  if (!validated) return Error("arguments", "Invalid Pomo input region");
  cairo_region_destroy(validated);
  g_object_set_data_full(G_OBJECT(window), "mvd-pomo-input-regions", fl_value_ref(regions),
      reinterpret_cast<GDestroyNotify>(fl_value_unref));
  g_object_set_data(G_OBJECT(window), "mvd-pomo-input-refresh", reinterpret_cast<gpointer>(RefreshInput));
  RefreshInput(window);
  if (!g_object_get_data(G_OBJECT(window), "mvd-pomo-map-hook")) {
    g_signal_connect(window, "map", G_CALLBACK(+[](GtkWidget* widget, gpointer) {
      RefreshInput(GTK_WINDOW(widget));
    }), nullptr);
    g_signal_connect(window, "size-allocate", G_CALLBACK(+[](GtkWidget* widget, GtkAllocation*, gpointer) {
      RefreshInput(GTK_WINDOW(widget));
    }), nullptr);
    g_object_set_data(G_OBJECT(window), "mvd-pomo-map-hook", GINT_TO_POINTER(1));
  }
  return OkResponse();
}

void multiview_desktop_linux_pomo_call(FlMethodCall* call) {
  const char* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (g_str_equal(method, "environment") && !mvd_gnome_context() &&
      g_str_equal(Backend(), "wayland") && gtk_layer_is_supported() && gtk_layer_get_protocol_version() >= 4) {
    struct PendingAreaReply { FlMethodCall* call; gint64 deadline; };
    ++layer_area_requests;
    EnsureLayerAreas(true);
    auto* pending = new PendingAreaReply{FL_METHOD_CALL(g_object_ref(call)), g_get_monotonic_time() + 750000};
    g_timeout_add_full(G_PRIORITY_DEFAULT, 5, +[](gpointer data) -> gboolean {
      auto* pending = static_cast<PendingAreaReply*>(data);
      PruneLayerAreas();
      if (!LayerAreasReady() && g_get_monotonic_time() < pending->deadline) return G_SOURCE_CONTINUE;
      g_autoptr(FlValue) environment = Environment();
      Respond(pending->call, environment, nullptr);
      return G_SOURCE_REMOVE;
    }, pending, +[](gpointer data) {
      auto* pending = static_cast<PendingAreaReply*>(data);
      g_object_unref(pending->call); delete pending;
      --layer_area_requests; RetireIdleLayerProbes();
    });
    return;
  }
  if (mvd_gnome_context() && g_str_equal(method, "setFollowing")) {
    FlValue* enabled = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(args, "enabled") : nullptr;
    if (!enabled || fl_value_get_type(enabled) != FL_VALUE_TYPE_BOOL) {
      Respond(call, nullptr, "Invalid GNOME following lease"); return;
    }
    g_object_ref(call);
    mvd_gnome_following(fl_value_get_bool(enabled), [call](const char* error) {
      Respond(call, nullptr, error); g_object_unref(call);
    });
    return;
  }
  if (mvd_gnome_context() && (g_str_equal(method, "environment") ||
      g_str_equal(method, "gnomeExtensionStatus") || g_str_equal(method, "installGnomeExtension") ||
      g_str_equal(method, "enableGnomeExtension"))) {
    g_object_ref(call);
    auto complete = [call]() {
      g_autoptr(FlValue) environment = Environment(); Respond(call, environment, nullptr); g_object_unref(call);
    };
    if (g_str_equal(method, "installGnomeExtension")) mvd_gnome_install(true, std::move(complete));
    else if (g_str_equal(method, "enableGnomeExtension")) mvd_gnome_install(false, std::move(complete));
    else mvd_gnome_status(std::move(complete));
    return;
  }
  FlValue* id = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(args, "viewId") : nullptr;
  auto wm = id && fl_value_get_type(id) == FL_VALUE_TYPE_INT ? MvdLinuxWindow::Find(fl_value_get_int(id)) : nullptr;
  if (wm && wm->is_pomo && mvd_gnome_window(wm->window) &&
      (g_str_equal(method, "bounds") || g_str_equal(method, "move") || g_str_equal(method, "configure") ||
       g_str_equal(method, "detach") || g_str_equal(method, "dragBegin") ||
       g_str_equal(method, "dragPosition") || g_str_equal(method, "dragEnd"))) {
    // Input regions belong to GTK; Shell alone owns global geometry.
    if (g_str_equal(method, "configure") || g_str_equal(method, "detach")) {
      g_autoptr(FlMethodResponse) local = multiview_desktop_linux_pomo_method(method, args);
      if (FL_IS_METHOD_ERROR_RESPONSE(local)) { fl_method_call_respond(call, local, nullptr); return; }
      if (g_str_equal(method, "configure") && mvd_gnome_command_is_local(method, args, true)) {
        // GTK input masks do not alter Shell geometry or cancel its drag.
        fl_method_call_respond(call, local, nullptr); return;
      }
    }
    g_object_ref(call);
    mvd_gnome_command(wm->window, method, args, [call](FlValue* result, const char* error) {
      Respond(call, result, error); g_object_unref(call);
    });
    return;
  }
  g_autoptr(FlMethodResponse) response = multiview_desktop_linux_pomo_method(method, args);
  fl_method_call_respond(call, response, nullptr);
}
}  // extern "C"
