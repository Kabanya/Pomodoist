#include <multiview_desktop/multiview_desktop_plugin.h>

#include "mvd_linux_internal.h"
#include "mvd_linux_log.h"
#include "mvd_linux_taskbar_menu.h"
#include "mvd_linux_window.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <map>
#include <memory>
#include <mutex>
#include <string>

#define MVD_LOG MVD_LOG_PLUGIN

namespace {

FlMethodChannel* g_channel = nullptr;
FlMethodChannel* g_screen_channel = nullptr;
FlEventChannel* g_screen_event_channel = nullptr;
FlValue* g_screen_event_sink = nullptr;

MvdWindowCreatedCallback g_create_cb = nullptr;
gboolean g_terminate_after_last_window_closed = TRUE;
int64_t g_anchor_view_id = -1;

struct PendingCreate {
  int64_t token = 0;
  double width = 800;
  double height = 600;
  std::string title;
  std::string title_bar_style;
  bool window_button_visibility = true;
  bool has_position = false;
  double pos_x = 0;
  double pos_y = 0;
};

std::mutex g_pending_mtx;
std::map<int64_t, PendingCreate> g_pending_create;

static gpointer view_id_to_pointer(int64_t view_id) {
  return GSIZE_TO_POINTER(static_cast<gsize>(view_id));
}

static int64_t pointer_to_view_id(gpointer data) {
  return static_cast<int64_t>(GPOINTER_TO_SIZE(data));
}

static int64_t int64_from_map(FlValue* args, const char* key) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return 0;
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (!v || fl_value_get_type(v) != FL_VALUE_TYPE_INT) {
    return 0;
  }
  return fl_value_get_int(v);
}

static double double_from_map(FlValue* args, const char* key, double fallback) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (!v) {
    return fallback;
  }
  if (fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT) {
    return fl_value_get_float(v);
  }
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT) {
    return static_cast<double>(fl_value_get_int(v));
  }
  return fallback;
}

static bool bool_from_map(FlValue* args, const char* key, bool fallback) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (!v || fl_value_get_type(v) != FL_VALUE_TYPE_BOOL) {
    return fallback;
  }
  return fl_value_get_bool(v);
}

static const char* string_from_map(FlValue* args, const char* key) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return "";
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (!v || fl_value_get_type(v) != FL_VALUE_TYPE_STRING) {
    return "";
  }
  return fl_value_get_string(v);
}

static FlMethodResponse* ok_null() {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* ok_bool(bool v) {
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(v)));
}

static FlMethodResponse* ok_string(const char* s) {
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_string(s ? s : "")));
}

static FlMethodResponse* ok_value(FlValue* v) {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(v));
}

static FlMethodResponse* err(const char* code, const char* message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message, nullptr));
}

static void emit_event(const char* event_name, int64_t view_id) {
  MVD_LOG("emit_event  '%s'  viewId=%" G_GINT64_FORMAT
          "  channel=%p",
          event_name, view_id, static_cast<void*>(g_channel));
  if (!g_channel) {
    MVD_LOG("emit_event  SKIP: g_channel is null");
    return;
  }
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "eventName", fl_value_new_string(event_name));
  fl_value_set_string_take(map, "viewId", fl_value_new_int(view_id));
  fl_method_channel_invoke_method(g_channel, "onEvent", map, nullptr, nullptr,
                                  nullptr);
  MVD_LOG("emit_event  dispatched  '%s'  viewId=%" G_GINT64_FORMAT,
          event_name, view_id);
}

static void emit_view_created(int64_t view_id, int64_t token) {
  MVD_LOG("emit_view_created  viewId=%" G_GINT64_FORMAT
          "  token=%" G_GINT64_FORMAT "  channel=%p",
          view_id, token, static_cast<void*>(g_channel));
  if (!g_channel) {
    MVD_LOG("emit_view_created  SKIP: g_channel is null");
    return;
  }
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "eventName", fl_value_new_string("viewCreated"));
  fl_value_set_string_take(map, "viewId", fl_value_new_int(view_id));
  fl_value_set_string_take(map, "token", fl_value_new_int(token));
  fl_method_channel_invoke_method(g_channel, "onEvent", map, nullptr, nullptr,
                                  nullptr);
  MVD_LOG("emit_view_created  dispatched  viewId=%" G_GINT64_FORMAT
          "  token=%" G_GINT64_FORMAT, view_id, token);
}

static gboolean on_delete(GtkWidget* widget, GdkEvent*, gpointer data) {
  const int64_t view_id = pointer_to_view_id(data);
  MVD_LOG("on_delete  START  viewId=%" G_GINT64_FORMAT "  widget=%p",
          view_id, static_cast<void*>(widget));

  auto wm = MvdLinuxWindow::Find(view_id);
  if (!wm) {
    MVD_LOG("on_delete  viewId=%" G_GINT64_FORMAT
            "  wm NOT FOUND in registry, returning FALSE (allow GTK destroy)",
            view_id);
    return FALSE;
  }

  MVD_LOG("on_delete  viewId=%" G_GINT64_FORMAT
          "  wm=%p  window=%p  view=%p",
          view_id, static_cast<void*>(wm.get()),
          static_cast<void*>(wm->window),
          static_cast<void*>(wm->view));
  MVD_LOG("on_delete  viewId=%" G_GINT64_FORMAT
          "  is_pre_confirm=%d  is_prevent_close=%d  is_confirm_close=%d"
          "  is_modal=%d  is_dialog=%d  modal_owner=%" G_GINT64_FORMAT,
          view_id,
          static_cast<int>(wm->is_pre_confirm),
          static_cast<int>(wm->is_prevent_close),
          static_cast<int>(wm->is_confirm_close),
          static_cast<int>(wm->is_modal),
          static_cast<int>(wm->is_dialog),
          wm->modal_owner_view_id);

  if (!wm->is_pre_confirm) {
    MVD_LOG("on_delete  viewId=%" G_GINT64_FORMAT
            "  is_pre_confirm=false -> emitting 'preconfirm-close'"
            " (blocking GTK delete, returning TRUE)", view_id);
    emit_event("preconfirm-close", view_id);
    return TRUE;
  }
  if (wm->is_prevent_close) {
    MVD_LOG("on_delete  viewId=%" G_GINT64_FORMAT
            "  is_prevent_close=true -> emitting 'close'"
            " (blocking GTK delete, returning TRUE)", view_id);
    emit_event("close", view_id);
    return TRUE;
  }
  if (!wm->is_confirm_close) {
    MVD_LOG("on_delete  viewId=%" G_GINT64_FORMAT
            "  is_confirm_close=false -> emitting 'confirm-close'"
            " (blocking GTK delete, returning TRUE)", view_id);
    emit_event("confirm-close", view_id);
    return TRUE;
  }

  // All checks passed - proceed with actual window destruction.
  const bool was_modal = wm->is_modal;
  const int64_t owner_id = wm->modal_owner_view_id;
  MVD_LOG("on_delete  viewId=%" G_GINT64_FORMAT
          "  FINAL CLOSE: emitting 'close', was_modal=%d, owner_id=%"
          G_GINT64_FORMAT,
          view_id, static_cast<int>(was_modal), owner_id);
  emit_event("close", view_id);

  MVD_LOG("on_delete  viewId=%" G_GINT64_FORMAT
          "  calling Unregister (shared_ptr refcount before erase=%ld)",
          view_id, wm.use_count());
  MvdLinuxWindow::Unregister(view_id);
  MVD_LOG("on_delete  viewId=%" G_GINT64_FORMAT
          "  Unregister done (shared_ptr refcount after=%ld)",
          view_id, wm.use_count());

  if (was_modal && owner_id >= 0) {
    MVD_LOG("on_delete  viewId=%" G_GINT64_FORMAT
            "  was modal, updating modal state layer for owner=%"
            G_GINT64_FORMAT, view_id, owner_id);
    MvdLinuxWindow::UpdateModalStateLayer(owner_id);
    MvdLinuxWindow::FocusModalTarget(
        MvdLinuxWindow::GetActiveModalFocusTarget(owner_id));
  }

  // Determine now (before the async delay) whether we should quit the app.
  //
  // Two independent conditions can require a quit:
  //   1. g_terminate_after_last_window_closed is true and there are no more
  //      registered windows (Dart-controlled policy).
  //   2. The last registered window was the primary/implicit view (view_id==0).
  //      Flutter's engine will terminate on its own when the implicit FlView
  //      is destroyed, but we still call g_application_quit to ensure the
  //      GApplication main loop exits cleanly if Flutter somehow doesn't.
  const bool should_quit = [&]() -> bool {
    std::lock_guard<std::mutex> lock(MvdLinuxWindow::registry_mtx);
    if (MvdLinuxWindow::windows.empty()) {
      // All windows closed: quit if the policy says so, OR if this was the
      // primary window (view_id==0), which always implies the app should exit.
      return g_terminate_after_last_window_closed || (view_id == 0);
    }
    return false;
  }();

  // Deferred destroy - the root of the X11/GLX crash.
  //
  // Problem: returning FALSE from delete-event lets GTK destroy the GtkWindow
  // immediately and synchronously.  The underlying X11 XID is freed on this
  // thread, but Flutter's raster thread (running at 60 fps) still has frames
  // queued for this view.  It calls glXMakeCurrent / glXSwapBuffers on the
  // now-dead XID -> the GLX call returns False -> Flutter's FML_CHECK aborts.
  // Suppressing the X11 error notification alone is not enough because the
  // GLX API return value (False) still triggers Flutter's internal fatal check.
  //
  // Fix: return TRUE (block GTK's immediate destroy), hide the window for
  // instant visual feedback, then schedule gtk_widget_destroy 100 ms later.
  //
  // During those 100 ms:
  //   - Dart processes the 'close' event and removes the view from the widget
  //     tree (~1-2 frames, <=32 ms).
  //   - Flutter's framework marks nothing dirty for this now-empty view, so
  //     the raster thread stops generating frames for it.
  //   - By the time gtk_widget_destroy fires, the raster thread is idle for
  //     this view -> fl_view_dispose -> FlutterEngineRemoveView runs cleanly
  //     with no pending GL work -> GLX surface properly destroyed before the
  //     X11 XID is freed -> no race, no crash.
  //
  // The X11 error handler installed in runner_install() remains as a safety
  // net for any residual errors from frames that were already in flight.

  MVD_LOG("on_delete  viewId=%" G_GINT64_FORMAT
          "  hiding window immediately (visual feedback)  widget=%p",
          view_id, static_cast<void*>(widget));
  gtk_widget_hide(widget);

  // Hold an extra GObject ref so the window stays alive through the timer.
  g_object_ref(widget);

  struct DeferredCtx {
    GtkWidget* widget;
    bool       should_quit;
    int64_t    view_id;   // for logging only
  };
  auto* ctx = new DeferredCtx{widget, should_quit, view_id};

  MVD_LOG("on_delete  viewId=%" G_GINT64_FORMAT
          "  scheduling deferred gtk_widget_destroy in 100 ms  widget=%p"
          "  should_quit=%d",
          view_id, static_cast<void*>(widget),
          static_cast<int>(should_quit));

  g_timeout_add(
      100,  // ms - 6+ Flutter frames; enough for Dart to clear the view tree
      [](gpointer data) -> gboolean {
        std::unique_ptr<DeferredCtx> c(static_cast<DeferredCtx*>(data));
        MVD_LOG("on_delete  deferred_destroy_cb  viewId=%" G_GINT64_FORMAT
                "  calling gtk_widget_destroy  widget=%p",
                c->view_id, static_cast<void*>(c->widget));
        gtk_widget_destroy(c->widget);
        MVD_LOG("on_delete  deferred_destroy_cb  viewId=%" G_GINT64_FORMAT
                "  gtk_widget_destroy returned  releasing extra GObject ref",
                c->view_id);
        g_object_unref(c->widget);  // release the ref we took before the timer
        if (c->should_quit) {
          GApplication* app = g_application_get_default();
          MVD_LOG("on_delete  deferred_destroy_cb  viewId=%" G_GINT64_FORMAT
                  "  last window closed, calling g_application_quit  app=%p",
                  c->view_id, static_cast<void*>(app));
          if (app) {
            g_application_quit(app);
          }
        }
        return G_SOURCE_REMOVE;
      },
      ctx);

  MVD_LOG("on_delete  viewId=%" G_GINT64_FORMAT
          "  returning TRUE (deferred destroy scheduled, GTK immediate destroy blocked)",
          view_id);
  return TRUE;
}

static gboolean on_focus_in(GtkWidget*, GdkEvent*, gpointer data) {
  emit_event("focus", pointer_to_view_id(data));
  return FALSE;
}

static gboolean on_focus_out(GtkWidget*, GdkEvent*, gpointer data) {
  emit_event("blur", pointer_to_view_id(data));
  return FALSE;
}

static gboolean on_configure(GtkWidget*, GdkEvent* event, gpointer data) {
  const int64_t view_id = pointer_to_view_id(data);
  if (!event || event->type != GDK_CONFIGURE) {
    return FALSE;
  }
  auto wm = MvdLinuxWindow::Find(view_id);
  if (wm) {
    wm->HandleConfigureEvent(&event->configure);
    wm->RefreshShadowCache();
    if (wm->is_modal) {
      wm->ClampToParentBounds();
    }
  }
  return FALSE;
}

static void on_map(GtkWidget*, gpointer data) {
  const int64_t view_id = pointer_to_view_id(data);
  auto wm = MvdLinuxWindow::Find(view_id);
  if (wm) {
    wm->SeedConfigureBaseline();
    wm->ReapplyGeometryHints();
  }
}

static void on_show(GtkWidget*, gpointer data) {
  const int64_t view_id = pointer_to_view_id(data);
  auto wm = MvdLinuxWindow::Find(view_id);
  if (wm) {
    wm->EmitShow();
  }
}

static void on_hide(GtkWidget*, gpointer data) {
  const int64_t view_id = pointer_to_view_id(data);
  auto wm = MvdLinuxWindow::Find(view_id);
  if (wm) {
    wm->EmitHide();
  }
}

// Re-apply geometry hints when the window leaves a maximized or fullscreen
// state (handled inside HandleWindowStateEvent).
static gboolean on_window_state(GtkWidget*, GdkEventWindowState* event,
                                gpointer data) {
  const int64_t view_id = pointer_to_view_id(data);
  auto wm = MvdLinuxWindow::Find(view_id);
  if (!wm) {
    return FALSE;
  }
  wm->HandleWindowStateEvent(event);
  return FALSE;
}

static void connect_window_signals(GtkWindow* window, int64_t view_id) {
  MVD_LOG("connect_window_signals  viewId=%" G_GINT64_FORMAT "  window=%p",
          view_id, static_cast<void*>(window));
  gpointer id_data = view_id_to_pointer(view_id);
  g_signal_connect(window, "delete-event", G_CALLBACK(on_delete), id_data);
  g_signal_connect(window, "focus-in-event", G_CALLBACK(on_focus_in), id_data);
  g_signal_connect(window, "focus-out-event", G_CALLBACK(on_focus_out), id_data);
  g_signal_connect(window, "configure-event", G_CALLBACK(on_configure), id_data);
  g_signal_connect(window, "map", G_CALLBACK(on_map), id_data);
  g_signal_connect(window, "show", G_CALLBACK(on_show), id_data);
  g_signal_connect(window, "hide", G_CALLBACK(on_hide), id_data);
  g_signal_connect(window, "window-state-event",
                   G_CALLBACK(on_window_state), id_data);
  MVD_LOG("connect_window_signals  DONE  viewId=%" G_GINT64_FORMAT
          "  connected: delete-event focus-in-event focus-out-event"
          " configure-event map show hide window-state-event", view_id);
}

static void register_window(GtkWindow* window, FlView* view, int64_t view_id,
                            bool is_dialog = false, bool is_modal = false,
                            int64_t dialog_parent_view_id = -1) {
  MVD_LOG("register_window  START  viewId=%" G_GINT64_FORMAT
          "  window=%p  view=%p  is_dialog=%d  is_modal=%d"
          "  dialog_parent_id=%" G_GINT64_FORMAT,
          view_id, static_cast<void*>(window), static_cast<void*>(view),
          static_cast<int>(is_dialog), static_cast<int>(is_modal),
          dialog_parent_view_id);
  auto wm = std::make_shared<MvdLinuxWindow>();
  wm->view_id = view_id;
  wm->window = window;
  wm->view = view;
  wm->is_dialog = is_dialog;
  wm->is_modal = is_modal;
  wm->dialog_parent_view_id = dialog_parent_view_id;
  wm->modal_owner_view_id = is_modal ? dialog_parent_view_id : -1;
  wm->SetEventEmitter([view_id](const char* event) { emit_event(event, view_id); });
  {
    std::lock_guard<std::mutex> lock(MvdLinuxWindow::registry_mtx);
    MvdLinuxWindow::windows[view_id] = wm;
    MVD_LOG("register_window  inserted into registry  total_windows=%zu",
            MvdLinuxWindow::windows.size());
  }
  // FlView quits the app on delete-event; multiview_desktop handles close itself.
  MVD_LOG("register_window  detaching Flutter quit-on-delete handler"
          "  viewId=%" G_GINT64_FORMAT, view_id);
  mvd_linux_detach_flutter_quit_on_window_close(window, view);
  connect_window_signals(window, view_id);
  MVD_LOG("register_window  DONE  viewId=%" G_GINT64_FORMAT, view_id);
}

struct DialogCreateParams {
  int64_t token = 0;
  int64_t parent_id = 0;
  int width = 400;
  int height = 300;
  bool is_modal = false;
  bool has_position = false;
  int pos_x = 0;
  int pos_y = 0;
  bool window_button_visibility = true;
  std::string title;
  std::string title_bar_style;
};

static void dialog_first_frame_cb(gpointer /*user_data*/, FlView* view) {
  const int64_t view_id = fl_view_get_id(view);
  auto wm = MvdLinuxWindow::Find(view_id);
  if (wm && wm->is_dialog && wm->dialog_parent_view_id >= 0) {
    wm->CenterOnDialogParent();
    if (wm->is_modal) {
      wm->ClampToParentBounds();
    }
  }
  GtkWidget* top = gtk_widget_get_toplevel(GTK_WIDGET(view));
  gtk_widget_show(top);
  gtk_widget_grab_focus(GTK_WIDGET(view));
}

static void create_modal_dialog_impl(const DialogCreateParams& params) {
  auto parent_wm = MvdLinuxWindow::Find(params.parent_id);
  if (!parent_wm || !parent_wm->window || !parent_wm->view) {
    return;
  }

  GApplication* app = g_application_get_default();
  if (!app) {
    return;
  }

  FlEngine* engine = fl_view_get_engine(parent_wm->view);
  if (!engine) {
    return;
  }

  const char* title =
      params.title.empty() ? "Flutter" : params.title.c_str();

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(app)));
  MvdLinuxWindow::DecorateToplevel(window, title);
  gtk_window_set_default_size(window, params.width, params.height);
  gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_DIALOG);

  if (params.is_modal) {
    gtk_window_set_transient_for(window, parent_wm->window);
    // gtk_window_set_modal blocks the entire application on GTK3. Parent-only
    // blocking is handled via UpdateModalStateLayer (see Windows GW_OWNER path).
    gtk_window_set_modal(window, FALSE);
  } else {
    gtk_window_set_modal(window, FALSE);
  }

  FlView* view = fl_view_new_for_engine(engine);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(dialog_first_frame_cb),
                           nullptr);

  gtk_widget_realize(GTK_WIDGET(view));

  const int64_t view_id = fl_view_get_id(view);
  register_window(window, view, view_id, true, params.is_modal,
                  params.parent_id);

  auto wm = MvdLinuxWindow::Find(view_id);
  if (wm && !params.title_bar_style.empty()) {
    wm->SetTitleBarStyle(params.title_bar_style.c_str(),
                         params.window_button_visibility);
  }

  if (wm && wm->dialog_parent_view_id >= 0) {
    wm->CenterOnDialogParent();
    if (wm->is_modal) {
      wm->ClampToParentBounds();
    }
  }

  if (params.is_modal) {
    gtk_widget_show(GTK_WIDGET(window));
    gtk_widget_show(GTK_WIDGET(view));
    gtk_window_present(window);
    gtk_widget_grab_focus(GTK_WIDGET(view));
    MvdLinuxWindow::UpdateModalStateLayer(params.parent_id);
  }

  emit_view_created(view_id, params.token);
}

static FlValue* display_to_map(GdkMonitor* monitor, int index) {
  GdkRectangle geo{};
  GdkRectangle work{};
  gdk_monitor_get_geometry(monitor, &geo);
  gdk_monitor_get_workarea(monitor, &work);

  // On X11, GDK returns physical pixel coordinates from gdk_monitor_get_geometry
  // and gdk_monitor_get_workarea. gdk_device_get_position also returns physical
  // pixels. All GTK window operations (gtk_window_move, gtk_window_get_position,
  // gtk_window_get_size) also use physical X11 coordinates.
  //
  // Dividing by gdk_monitor_get_scale_factor would mismatch the coordinate
  // system used by the cursor and window APIs, producing wrong results when
  // the scale factor is > 1 (e.g. HiDPI or fractional-scaling setups).
  //
  // multi_window_manager uses the same approach: no division by scale.
  const int scale = gdk_monitor_get_scale_factor(monitor);
  const char* model = gdk_monitor_get_model(monitor);

  FlValue* map = fl_value_new_map();
  gchar* id = g_strdup_printf("%d", index);
  fl_value_set_string_take(map, "id", fl_value_new_string(id));
  g_free(id);
  fl_value_set_string_take(map, "name",
                           fl_value_new_string(model ? model : ""));

  FlValue* size = fl_value_new_map();
  fl_value_set_string_take(size, "width",
                           fl_value_new_float(static_cast<double>(geo.width)));
  fl_value_set_string_take(size, "height",
                           fl_value_new_float(static_cast<double>(geo.height)));
  fl_value_set_string_take(map, "size", size);

  FlValue* vis_pos = fl_value_new_map();
  fl_value_set_string_take(vis_pos, "dx",
                           fl_value_new_float(static_cast<double>(work.x)));
  fl_value_set_string_take(vis_pos, "dy",
                           fl_value_new_float(static_cast<double>(work.y)));
  fl_value_set_string_take(map, "visiblePosition", vis_pos);

  FlValue* vis_size = fl_value_new_map();
  fl_value_set_string_take(vis_size, "width",
                           fl_value_new_float(static_cast<double>(work.width)));
  fl_value_set_string_take(vis_size, "height",
                           fl_value_new_float(static_cast<double>(work.height)));
  fl_value_set_string_take(map, "visibleSize", vis_size);

  fl_value_set_string_take(map, "scaleFactor",
                           fl_value_new_float(static_cast<double>(scale)));
  return map;
}

static void handle_screen_method(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  GdkDisplay* display = gdk_display_get_default();

  if (g_strcmp0(method, "getCursorScreenPoint") == 0) {
    GdkSeat* seat = gdk_display_get_default_seat(display);
    GdkDevice* pointer = gdk_seat_get_pointer(seat);
    gint x = 0;
    gint y = 0;
    gdk_device_get_position(pointer, nullptr, &x, &y);
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "dx", fl_value_new_float(x));
    fl_value_set_string_take(map, "dy", fl_value_new_float(y));
    response = ok_value(map);
  } else if (g_strcmp0(method, "getPrimaryDisplay") == 0) {
    GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
    if (!monitor) {
      const int n = gdk_display_get_n_monitors(display);
      if (n > 0) {
        monitor = gdk_display_get_monitor(display, 0);
      }
    }
    if (!monitor) {
      response = err("NO_SCREEN", "No primary display found");
    } else {
      response = ok_value(display_to_map(monitor, 0));
    }
  } else if (g_strcmp0(method, "getAllDisplays") == 0) {
    const int n = gdk_display_get_n_monitors(display);
    FlValue* list = fl_value_new_list();
    for (int i = 0; i < n; i++) {
      GdkMonitor* mon = gdk_display_get_monitor(display, i);
      fl_value_append_take(list, display_to_map(mon, i));
    }
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "displays", list);
    response = ok_value(map);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_view_method(FlMethodCall* method_call,
                               const std::shared_ptr<MvdLinuxWindow>& wm) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "closeWindow") == 0) {
    MVD_LOG("handle_view_method  closeWindow  viewId=%" G_GINT64_FORMAT
            "  wm=%p  window=%p  view=%p",
            wm->view_id, static_cast<void*>(wm.get()),
            static_cast<void*>(wm->window), static_cast<void*>(wm->view));
    wm->Close();
    MVD_LOG("handle_view_method  closeWindow  Close() returned"
            "  viewId=%" G_GINT64_FORMAT, wm->view_id);
    response = ok_null();
  } else if (g_strcmp0(method, "destroyWindow") == 0) {
    MVD_LOG("handle_view_method  destroyWindow  viewId=%" G_GINT64_FORMAT
            "  wm=%p  window=%p  view=%p",
            wm->view_id, static_cast<void*>(wm.get()),
            static_cast<void*>(wm->window), static_cast<void*>(wm->view));
    wm->Destroy();
    MVD_LOG("handle_view_method  destroyWindow  Destroy() returned"
            "  viewId=%" G_GINT64_FORMAT, wm->view_id);
    response = ok_null();
  } else if (g_strcmp0(method, "isPreventClose") == 0) {
    response = ok_bool(wm->is_prevent_close);
  } else if (g_strcmp0(method, "setPreventClose") == 0) {
    wm->is_prevent_close =
        bool_from_map(args, "isPreventClose", wm->is_prevent_close);
    response = ok_null();
  } else if (g_strcmp0(method, "confirmClose") == 0) {
    wm->is_confirm_close = bool_from_map(args, "confirmClose", true);
    response = ok_null();
  } else if (g_strcmp0(method, "preConfirmClose") == 0) {
    wm->is_pre_confirm = bool_from_map(args, "preConfirmClose", false);
    response = ok_null();
  } else if (g_strcmp0(method, "setTitle") == 0) {
    wm->SetTitle(string_from_map(args, "title"));
    response = ok_null();
  } else if (g_strcmp0(method, "getTitle") == 0) {
    response = ok_string(wm->GetTitle());
  } else if (g_strcmp0(method, "getTitleBarStyle") == 0) {
    response = ok_value(wm->GetTitleBarStyle());
  } else if (g_strcmp0(method, "setTitleBarStyle") == 0) {
    wm->SetTitleBarStyle(
        string_from_map(args, "titleBarStyle"),
        bool_from_map(args, "windowButtonVisibility", true));
    response = ok_null();
  } else if (g_strcmp0(method, "setAsFrameless") == 0) {
    wm->SetAsFrameless();
    response = ok_null();
  } else if (g_strcmp0(method, "show") == 0) {
    wm->Show();
    response = ok_null();
  } else if (g_strcmp0(method, "hide") == 0) {
    wm->Hide();
    response = ok_null();
  } else if (g_strcmp0(method, "isVisible") == 0) {
    response = ok_bool(wm->IsVisible());
  } else if (g_strcmp0(method, "focus") == 0) {
    wm->Focus();
    response = ok_null();
  } else if (g_strcmp0(method, "blur") == 0) {
    response = ok_null();
  } else if (g_strcmp0(method, "isFocused") == 0) {
    response = ok_bool(wm->IsFocused());
  } else if (g_strcmp0(method, "isOnActiveSpace") == 0) {
    response = ok_bool(TRUE);
  } else if (g_strcmp0(method, "maximize") == 0) {
    wm->Maximize();
    response = ok_null();
  } else if (g_strcmp0(method, "unmaximize") == 0) {
    wm->Unmaximize();
    response = ok_null();
  } else if (g_strcmp0(method, "isMaximized") == 0) {
    response = ok_bool(wm->IsMaximized());
  } else if (g_strcmp0(method, "minimize") == 0) {
    wm->Minimize();
    response = ok_null();
  } else if (g_strcmp0(method, "restore") == 0) {
    wm->Restore();
    response = ok_null();
  } else if (g_strcmp0(method, "isMinimized") == 0) {
    response = ok_bool(wm->IsMinimized());
  } else if (g_strcmp0(method, "isFullScreen") == 0) {
    response = ok_bool(wm->IsFullScreen());
  } else if (g_strcmp0(method, "setFullScreen") == 0) {
    wm->SetFullScreen(bool_from_map(args, "isFullScreen", false));
    response = ok_null();
  } else if (g_strcmp0(method, "getBounds") == 0) {
    response = ok_value(wm->GetBounds());
  } else if (g_strcmp0(method, "setSize") == 0) {
    wm->SetSize(double_from_map(args, "width", 800),
                double_from_map(args, "height", 600));
    response = ok_null();
  } else if (g_strcmp0(method, "setPosition") == 0) {
    // Dart sends x/y at the top level: _args(viewId, {'x': ..., 'y': ...})
    wm->SetPosition(double_from_map(args, "x", 0), double_from_map(args, "y", 0));
    response = ok_null();
  } else if (g_strcmp0(method, "center") == 0) {
    wm->Center();
    response = ok_null();
  } else if (g_strcmp0(method, "setMinimumSize") == 0) {
    wm->SetMinimumSize(static_cast<float>(double_from_map(args, "width", -1)),
                       static_cast<float>(double_from_map(args, "height", -1)));
    response = ok_null();
  } else if (g_strcmp0(method, "setMaximumSize") == 0) {
    wm->SetMaximumSize(static_cast<float>(double_from_map(args, "width", -1)),
                       static_cast<float>(double_from_map(args, "height", -1)));
    response = ok_null();
  } else if (g_strcmp0(method, "setAspectRatio") == 0) {
    wm->SetAspectRatio(static_cast<float>(double_from_map(args, "aspectRatio", -1)));
    response = ok_null();
  } else if (g_strcmp0(method, "isResizable") == 0) {
    response = ok_bool(wm->IsResizable());
  } else if (g_strcmp0(method, "setResizable") == 0) {
    wm->SetResizable(bool_from_map(args, "isResizable", true));
    response = ok_null();
  } else if (g_strcmp0(method, "isMovable") == 0) {
    response = ok_bool(wm->IsMovable());
  } else if (g_strcmp0(method, "setMovable") == 0) {
    wm->SetMovable(bool_from_map(args, "isMovable", true));
    response = ok_null();
  } else if (g_strcmp0(method, "isMinimizable") == 0) {
    response = ok_bool(wm->IsMinimizable());
  } else if (g_strcmp0(method, "setMinimizable") == 0) {
    wm->SetMinimizable(bool_from_map(args, "isMinimizable", true));
    response = ok_null();
  } else if (g_strcmp0(method, "isMaximizable") == 0) {
    response = ok_bool(wm->IsMaximizable());
  } else if (g_strcmp0(method, "setMaximizable") == 0) {
    wm->SetMaximizable(bool_from_map(args, "isMaximizable", true));
    response = ok_null();
  } else if (g_strcmp0(method, "isClosable") == 0) {
    response = ok_bool(wm->IsClosable());
  } else if (g_strcmp0(method, "setClosable") == 0) {
    wm->SetClosable(bool_from_map(args, "isClosable", true));
    response = ok_null();
  } else if (g_strcmp0(method, "isAlwaysOnTop") == 0) {
    response = ok_bool(wm->IsAlwaysOnTop());
  } else if (g_strcmp0(method, "setAlwaysOnTop") == 0) {
    wm->SetAlwaysOnTop(bool_from_map(args, "isAlwaysOnTop", false));
    response = ok_null();
  } else if (g_strcmp0(method, "hideAppFromTaskbar") == 0) {
    wm->SetSkipTaskbar(bool_from_map(args, "isHideAppFromTaskbar", false));
    response = ok_null();
  } else if (g_strcmp0(method, "hasShadow") == 0) {
    response = ok_bool(wm->HasShadow());
  } else if (g_strcmp0(method, "setHasShadow") == 0) {
    wm->SetHasShadow(bool_from_map(args, "hasShadow", true));
    response = ok_null();
  } else if (g_strcmp0(method, "getOpacity") == 0) {
    FlValue* v = fl_value_new_float(wm->GetOpacity());
    response = ok_value(v);
  } else if (g_strcmp0(method, "setOpacity") == 0) {
    wm->SetOpacity(double_from_map(args, "opacity", 1.0));
    response = ok_null();
  } else if (g_strcmp0(method, "setBrightness") == 0) {
    wm->SetBrightness(string_from_map(args, "brightness"));
    response = ok_null();
  } else if (g_strcmp0(method, "setBackgroundColor") == 0) {
    const int r = static_cast<int>(double_from_map(args, "red", 0));
    const int g = static_cast<int>(double_from_map(args, "green", 0));
    const int b = static_cast<int>(double_from_map(args, "blue", 0));
    const int a = static_cast<int>(double_from_map(args, "alpha", 255));
    wm->SetBackgroundColor(r, g, b, a);
    response = ok_null();
  } else if (g_strcmp0(method, "setIgnoreMouseEvents") == 0) {
    wm->SetIgnoreMouseEvents(bool_from_map(args, "ignore", false),
                             bool_from_map(args, "forward", false));
    response = ok_null();
  } else if (g_strcmp0(method, "isIgnoreMouseEvents") == 0) {
    auto [ignore, forward] = wm->IsIgnoreMouseEvents();
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "ignore", fl_value_new_bool(ignore));
    fl_value_set_string_take(map, "forward", fl_value_new_bool(forward));
    response = ok_value(map);
  } else if (g_strcmp0(method, "startDragging") == 0) {
    wm->StartDragging();
    response = ok_null();
  } else if (g_strcmp0(method, "startResizing") == 0) {
    wm->StartResizing(string_from_map(args, "edge"));
    response = ok_null();
  } else if (g_strcmp0(method, "popUpWindowMenu") == 0) {
    wm->PopUpWindowMenu();
    response = ok_null();
  } else if (g_strcmp0(method, "setBadgeLabel") == 0 ||
             g_strcmp0(method, "hideFromCollection") == 0 ||
             g_strcmp0(method, "isHideFromCollection") == 0 ||
             g_strcmp0(method, "isVisibleOnAllWorkspaces") == 0 ||
             g_strcmp0(method, "setVisibleOnAllWorkspaces") == 0) {
    response = ok_null();
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void method_cb(FlMethodChannel*, FlMethodCall* method_call, gpointer) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  // Log every incoming method call. High-frequency "resize" events are
  // excluded to avoid flooding the console.
  if (g_strcmp0(method, "getBounds") != 0 &&
      g_strcmp0(method, "isFocused") != 0) {
    MVD_LOG("method_cb  method='%s'  viewId=%" G_GINT64_FORMAT,
            method, int64_from_map(args, "viewId"));
  }

  if (g_strcmp0(method, "checkExistViewId") == 0) {
    const int64_t view_id = int64_from_map(args, "viewId");
    const bool exists = MvdLinuxWindow::Find(view_id) != nullptr;
    MVD_LOG("method_cb  checkExistViewId  viewId=%" G_GINT64_FORMAT
            "  exists=%d", view_id, static_cast<int>(exists));
    response = ok_bool(exists);
  } else if (g_strcmp0(method, "createWindow") == 0) {
    if (!g_create_cb) {
      MVD_LOG("method_cb  createWindow  ERROR: g_create_cb is null");
      response = err("createWindow", "WindowCreatedCallback not set in runner");
    } else {
      PendingCreate pending{};
      pending.token = int64_from_map(args, "token");
      pending.width = double_from_map(args, "width", 800);
      pending.height = double_from_map(args, "height", 600);
      pending.title = string_from_map(args, "title");
      pending.title_bar_style = string_from_map(args, "titleBarStyle");
      pending.window_button_visibility =
          bool_from_map(args, "windowButtonVisibility", true);
      FlValue* pos = fl_value_lookup_string(args, "position");
      if (pos && fl_value_get_type(pos) == FL_VALUE_TYPE_MAP) {
        pending.has_position = true;
        pending.pos_x = double_from_map(pos, "x", 0);
        pending.pos_y = double_from_map(pos, "y", 0);
      }
      MVD_LOG("method_cb  createWindow  token=%" G_GINT64_FORMAT
              "  size=%.0fx%.0f  title='%s'  title_bar_style='%s'"
              "  has_pos=%d  pos=(%.0f,%.0f)",
              pending.token, pending.width, pending.height,
              pending.title.c_str(), pending.title_bar_style.c_str(),
              static_cast<int>(pending.has_position),
              pending.pos_x, pending.pos_y);
      MvdCreateWindowRequest req{};
      req.token = pending.token;
      req.width = pending.width;
      req.height = pending.height;
      req.title = pending.title.c_str();
      req.title_bar_style = pending.title_bar_style.c_str();
      req.window_button_visibility = pending.window_button_visibility;
      req.has_position = pending.has_position ? TRUE : FALSE;
      req.pos_x = pending.pos_x;
      req.pos_y = pending.pos_y;
      // Call g_create_cb before moving pending; the callback copies strings async.
      MVD_LOG("method_cb  createWindow  calling g_create_cb  token=%"
              G_GINT64_FORMAT, req.token);
      g_create_cb(&req);
      MVD_LOG("method_cb  createWindow  g_create_cb returned  token=%"
              G_GINT64_FORMAT, req.token);
      {
        std::lock_guard<std::mutex> lk(g_pending_mtx);
        g_pending_create[pending.token] = std::move(pending);
        MVD_LOG("method_cb  createWindow  stored in pending_create  pending_count=%zu",
                g_pending_create.size());
      }
      response = ok_null();
    }
  } else if (g_strcmp0(method, "createModalDialog") == 0) {
    const int64_t parent_id = int64_from_map(args, "parentId");
    const bool is_modal = bool_from_map(args, "modal", false);
    if (MvdLinuxWindow::Find(parent_id) == nullptr) {
      MVD_LOG("method_cb  createModalDialog  ERROR: parent viewId=%"
              G_GINT64_FORMAT " not found", parent_id);
      response = err("NO_PARENT", "No parent window for viewId");
    } else {
      auto* params = new DialogCreateParams();
      params->token = int64_from_map(args, "token");
      params->parent_id = parent_id;
      params->width = static_cast<int>(double_from_map(args, "width", 400));
      params->height = static_cast<int>(double_from_map(args, "height", 300));
      params->is_modal = is_modal;
      params->title = string_from_map(args, "title");
      params->title_bar_style = string_from_map(args, "titleBarStyle");
      params->window_button_visibility =
          bool_from_map(args, "windowButtonVisibility", true);
      FlValue* pos = fl_value_lookup_string(args, "position");
      if (pos && fl_value_get_type(pos) == FL_VALUE_TYPE_MAP) {
        params->has_position = true;
        params->pos_x = static_cast<int>(double_from_map(pos, "x", 0));
        params->pos_y = static_cast<int>(double_from_map(pos, "y", 0));
      }
      MVD_LOG("method_cb  createModalDialog  token=%" G_GINT64_FORMAT
              "  parent_id=%" G_GINT64_FORMAT "  is_modal=%d"
              "  size=%dx%d  title='%s'",
              params->token, params->parent_id, static_cast<int>(params->is_modal),
              params->width, params->height, params->title.c_str());
      MVD_LOG("method_cb  createModalDialog  dispatching to main thread"
              " via g_main_context_invoke");
      g_main_context_invoke(
          nullptr,
          [](gpointer data) -> gboolean {
            std::unique_ptr<DialogCreateParams> params(
                static_cast<DialogCreateParams*>(data));
            MVD_LOG("method_cb  createModalDialog  main-thread callback"
                    "  token=%" G_GINT64_FORMAT "  parent_id=%" G_GINT64_FORMAT,
                    params->token, params->parent_id);
            create_modal_dialog_impl(*params);
            return G_SOURCE_REMOVE;
          },
          params);
      response = ok_null();
    }
  } else if (g_strcmp0(method, "setTerminateAfterLastWindowClosed") == 0) {
    g_terminate_after_last_window_closed =
        bool_from_map(args, "terminateAfterLastWindowClosed", true);
    response = ok_null();
  } else if (g_strcmp0(method, "setAnchorViewId") == 0) {
    g_anchor_view_id = int64_from_map(args, "viewId");
    response = ok_null();
  } else if (g_strcmp0(method, "isHideAppFromTaskbar") == 0) {
    bool all_hidden = true;
    std::lock_guard<std::mutex> lock(MvdLinuxWindow::registry_mtx);
    for (const auto& p : MvdLinuxWindow::windows) {
      if (!p.second->IsSkipTaskbar()) {
        all_hidden = false;
        break;
      }
    }
    response = ok_bool(all_hidden);
  } else if (g_strcmp0(method, "isHideAppTabFromTaskbar") == 0) {
    const int64_t view_id = int64_from_map(args, "viewId");
    auto wm = MvdLinuxWindow::Find(view_id);
    response = ok_bool(wm && wm->IsSkipTaskbar());
  } else if (g_strcmp0(method, "setProgressBar") == 0) {
    response = ok_null();
  } else if (g_strcmp0(method, "setTaskbarMenu") == 0) {
    mvd_linux_set_taskbar_menu(fl_value_lookup_string(args, "items"));
    response = ok_null();
  } else {
    const int64_t view_id = int64_from_map(args, "viewId");
    auto wm = MvdLinuxWindow::Find(view_id);
    if (!wm) {
      response = err("NO_WINDOW", "No window for viewId");
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    handle_view_method(method_call, wm);
    return;
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void screen_method_cb(FlMethodChannel*, FlMethodCall* method_call,
                             gpointer) {
  handle_screen_method(method_call);
}

static FlMethodErrorResponse* screen_stream_cancel_cb(FlEventChannel*,
                                                    FlValue*,
                                                    gpointer) {
  g_clear_pointer(&g_screen_event_sink, fl_value_unref);
  return nullptr;
}

static FlMethodErrorResponse* screen_stream_listen_cb(FlEventChannel*,
                                                      FlValue* args,
                                                      gpointer) {
  g_clear_pointer(&g_screen_event_sink, fl_value_unref);
  if (args) {
    g_screen_event_sink = fl_value_ref(args);
  }
  return nullptr;
}

}  // namespace

extern "C" {

void mvd_linux_set_window_created_callback(MvdWindowCreatedCallback callback) {
  g_create_cb = callback;
}

void mvd_linux_register_primary(GtkWindow* window, FlView* view) {
  g_return_if_fail(GTK_IS_WINDOW(window));
  g_return_if_fail(FL_IS_VIEW(view));
  const int64_t view_id = fl_view_get_id(view);
  MVD_LOG("register_primary  window=%p  view=%p  view_id=%" G_GINT64_FORMAT,
          static_cast<void*>(window), static_cast<void*>(view), view_id);
  register_window(window, view, view_id);
  if (g_anchor_view_id < 0) {
    g_anchor_view_id = view_id;
    MVD_LOG("register_primary  anchor_view_id set to %" G_GINT64_FORMAT,
            g_anchor_view_id);
  } else {
    MVD_LOG("register_primary  anchor_view_id already set to %"
            G_GINT64_FORMAT " (not overriding)", g_anchor_view_id);
  }
  MVD_LOG("register_primary  DONE  primary view_id=%" G_GINT64_FORMAT,
          view_id);
}

void mvd_linux_complete_secondary_window(GtkWindow* window,
                                                       FlView* view,
                                                       int64_t token) {
  g_return_if_fail(GTK_IS_WINDOW(window));
  g_return_if_fail(FL_IS_VIEW(view));

  MVD_LOG("complete_secondary_window  START  token=%" G_GINT64_FORMAT
          "  window=%p  view=%p", token,
          static_cast<void*>(window), static_cast<void*>(view));

  PendingCreate pending{};
  bool found_pending = false;
  {
    std::lock_guard<std::mutex> lk(g_pending_mtx);
    auto it = g_pending_create.find(token);
    if (it != g_pending_create.end()) {
      pending = std::move(it->second);
      g_pending_create.erase(it);
      found_pending = true;
    }
  }

  MVD_LOG("complete_secondary_window  token=%" G_GINT64_FORMAT
          "  pending_found=%d  pending_title='%s'"
          "  pending_title_bar_style='%s'  has_position=%d"
          "  size=%.0fx%.0f",
          token, static_cast<int>(found_pending),
          pending.title.c_str(), pending.title_bar_style.c_str(),
          static_cast<int>(pending.has_position),
          pending.width, pending.height);

  const int64_t view_id = fl_view_get_id(view);
  MVD_LOG("complete_secondary_window  token=%" G_GINT64_FORMAT
          "  view_id=%" G_GINT64_FORMAT, token, view_id);

  if (!pending.has_position) {
    MVD_LOG("complete_secondary_window  no explicit position -> GTK_WIN_POS_CENTER"
            "  viewId=%" G_GINT64_FORMAT, view_id);
    gtk_window_set_position(window, GTK_WIN_POS_CENTER);
  } else {
    MVD_LOG("complete_secondary_window  explicit position=(%.0f,%.0f)"
            "  viewId=%" G_GINT64_FORMAT,
            pending.pos_x, pending.pos_y, view_id);
  }

  MVD_LOG("complete_secondary_window  calling register_window"
          "  viewId=%" G_GINT64_FORMAT, view_id);
  register_window(window, view, view_id);

  auto wm = MvdLinuxWindow::Find(view_id);
  if (wm && !pending.title_bar_style.empty()) {
    MVD_LOG("complete_secondary_window  applying title_bar_style='%s'"
            "  wbv=%d  viewId=%" G_GINT64_FORMAT,
            pending.title_bar_style.c_str(),
            static_cast<int>(pending.window_button_visibility), view_id);
    wm->SetTitleBarStyle(pending.title_bar_style.c_str(),
                         pending.window_button_visibility);
  } else {
    MVD_LOG("complete_secondary_window  no title_bar_style to apply"
            "  viewId=%" G_GINT64_FORMAT, view_id);
  }

  MVD_LOG("complete_secondary_window  emitting viewCreated"
          "  viewId=%" G_GINT64_FORMAT "  token=%" G_GINT64_FORMAT,
          view_id, token);
  emit_view_created(view_id, token);
  MVD_LOG("complete_secondary_window  DONE  viewId=%" G_GINT64_FORMAT
          "  token=%" G_GINT64_FORMAT, view_id, token);
}

void mvd_linux_detach_flutter_quit_on_window_close(
    GtkWindow* window,
    FlView* view) {
  g_return_if_fail(GTK_IS_WINDOW(window));
  g_return_if_fail(FL_IS_VIEW(view));
  const guint signal_id = g_signal_lookup("delete-event", GTK_TYPE_WIDGET);
  MVD_LOG("detach_flutter_quit  window=%p  view=%p  signal_id=%u",
          static_cast<void*>(window), static_cast<void*>(view), signal_id);
  if (signal_id == 0) {
    MVD_LOG("detach_flutter_quit  SKIP: delete-event signal_id not found");
    return;
  }
  g_signal_handlers_disconnect_matched(
      G_OBJECT(window),
      static_cast<GSignalMatchType>(G_SIGNAL_MATCH_ID | G_SIGNAL_MATCH_DATA),
      signal_id, static_cast<GQuark>(0), nullptr, nullptr, view);
  MVD_LOG("detach_flutter_quit  disconnected Flutter's quit handler"
          "  window=%p  view=%p", static_cast<void*>(window),
          static_cast<void*>(view));
}

void multiview_desktop_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  MVD_LOG("register_with_registrar  START  registrar=%p",
          static_cast<void*>(registrar));
  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);
  MVD_LOG("register_with_registrar  messenger=%p",
          static_cast<void*>(messenger));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* ch = fl_method_channel_new(
      messenger, "multiview_desktop", FL_METHOD_CODEC(codec));
  if (g_channel) {
    MVD_LOG("register_with_registrar  replacing existing g_channel=%p"
            " with new ch=%p",
            static_cast<void*>(g_channel), static_cast<void*>(ch));
    g_object_unref(g_channel);
  }
  g_channel = ch;
  mvd_linux_taskbar_menu_set_channel(g_channel);
  MVD_LOG("register_with_registrar  MethodChannel 'multiview_desktop'"
          "  ch=%p", static_cast<void*>(ch));
  fl_method_channel_set_method_call_handler(g_channel, method_cb, nullptr,
                                            nullptr);

  FlMethodChannel* screen_ch = fl_method_channel_new(
      messenger, "multiview_desktop/screen_retriever", FL_METHOD_CODEC(codec));
  if (g_screen_channel) {
    g_object_unref(g_screen_channel);
  }
  g_screen_channel = screen_ch;
  fl_method_channel_set_method_call_handler(g_screen_channel, screen_method_cb,
                                            nullptr, nullptr);

  g_autoptr(FlStandardMethodCodec) event_codec = fl_standard_method_codec_new();
  FlEventChannel* event_ch = fl_event_channel_new(
      messenger, "multiview_desktop/screen_retriever_event",
      FL_METHOD_CODEC(event_codec));
  if (g_screen_event_channel) {
    g_object_unref(g_screen_event_channel);
  }
  g_screen_event_channel = event_ch;
  fl_event_channel_set_stream_handlers(
      g_screen_event_channel, screen_stream_listen_cb, screen_stream_cancel_cb,
      nullptr, nullptr);
  MVD_LOG("register_with_registrar  DONE"
          "  channels: main=%p screen=%p screen_event=%p",
          static_cast<void*>(g_channel),
          static_cast<void*>(g_screen_channel),
          static_cast<void*>(g_screen_event_channel));
}

}  // extern "C"
