#include <multiview_desktop/multiview_desktop_runner.h>

#include "mvd_linux_internal.h"
#include "mvd_linux_log.h"
#include "mvd_linux_window.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#include <X11/Xlib.h>
#endif

#include <gtk/gtk.h>

#include <memory>
#include <string>

#define MVD_LOG MVD_LOG_RUNNER

// X11 error handler - suppresses BadAccess from glXSwapBuffers.
//
// On X11 Flutter renders frames on a separate raster thread.
// When the user closes a window, GTK destroys GtkWindow -> GdkWindow -> XID.
// The raster thread may not know the window is dead yet and calls
// glXSwapBuffers(display, dead_XID).
// The X server returns BadAccess (error_code=10, minor_code=26).
// GDK's default handler calls _exit(1) -> the app crashes.
//
// This is a known race in Flutter's multi-threaded rendering pipeline on X11.
// The same bug exists in flutter/examples/multiple_windows.
// Chrome, Firefox, and Electron use a similar error handler.
//
// We suppress ONLY:
//   error_code  == BadAccess (10)
//   request_code == g_glx_opcode (major opcode GLX, usually ~149)
//   minor_code  == 26 (X_GLXSwapBuffers)
#ifdef GDK_WINDOWING_X11
namespace {
  int (*g_prev_x_error_handler)(Display*, XErrorEvent*) = nullptr;
  int g_glx_opcode = -1;
  // GLX defines its own error codes starting at error_base.
  // We store it so we can identify GLX extension errors (GLXBadDrawable etc.)
  // in addition to standard X11 errors like BadAccess.
  int g_glx_error_base = -1;

  static int mvd_x11_error_handler(Display* dpy, XErrorEvent* ev) {
    // Suppress ALL errors that originate from the GLX extension.
    //
    // Our plugin makes zero GLX calls - every GLX error comes from Flutter's
    // raster thread, which renders asynchronously. When a window is closed:
    //   1. GTK destroys GtkWindow -> GdkWindow -> X11 XID
    //   2. Flutter raster thread still has GL work queued for that XID and
    //      fires a chain of GLX requests on the now-dead drawable:
    //        serial N   : X_GLXMakeContextCurrent (minor=26) -> BadAccess
    //        serial N+1 : X_GLXGetDrawableAttributes (minor=29) -> GLXBadDrawable
    //        (possibly more...)
    //
    // All such errors are benign - the window is already invisible to the user.
    // GDK's default handler calls _exit(1), so we must intercept them here.
    //
    // This is the same pattern used by Chrome, Firefox and Electron for
    // GLX races during window destruction.
    if (g_glx_opcode > 0 &&
        ev->request_code == static_cast<unsigned char>(g_glx_opcode)) {
      MVD_LOG("x11_error_handler  [SUPPRESSED] GLX error"
              "  error_code=%d  minor_code=%d  serial=%lu  XID=0x%lx"
              "  (Flutter raster thread vs destroyed X11 window race)",
              ev->error_code, ev->minor_code,
              ev->serial,
              static_cast<unsigned long>(ev->resourceid));
      return 0;
    }
    // Non-GLX errors - forward to the previous handler (GDK's).
    if (g_prev_x_error_handler) {
      return g_prev_x_error_handler(dpy, ev);
    }
    return 0;
  }
}  // namespace
#endif

namespace {

FlEngine* g_shared_engine = nullptr;
GtkApplication* g_app = nullptr;
const char* g_default_title = "Flutter";

static void first_frame_cb(gpointer user_data, FlView* view) {
  const int skip = GPOINTER_TO_INT(user_data);
  const int64_t view_id = fl_view_get_id(view);
  MVD_LOG("first_frame_cb  view=%p  view_id=%" G_GINT64_FORMAT "  skip=%d",
          static_cast<void*>(view), view_id, skip);
  if (skip) {
    MVD_LOG("first_frame_cb  SKIP: skip flag set  view_id=%" G_GINT64_FORMAT,
            view_id);
    return;
  }
  GtkWidget* top = gtk_widget_get_toplevel(GTK_WIDGET(view));
  MVD_LOG("first_frame_cb  toplevel=%p  view_id=%" G_GINT64_FORMAT,
          static_cast<void*>(top), view_id);

  // Apply any position queued by setPosition() before the window was
  // mapped. This must happen BEFORE gtk_widget_show() so that the X11
  // MapRequest carries the correct PPosition hint instead of letting the
  // WM apply GTK_WIN_POS_CENTER.
  auto wm = MvdLinuxWindow::Find(view_id);
  if (wm) {
    MVD_LOG("first_frame_cb  has_pending_move=%d  view_id=%" G_GINT64_FORMAT,
            static_cast<int>(wm->has_pending_move), view_id);
    wm->ApplyPendingMove();
  } else {
    MVD_LOG("first_frame_cb  wm not found for view_id=%" G_GINT64_FORMAT
            "  (no pending move to apply)", view_id);
  }

  MVD_LOG("first_frame_cb  calling gtk_widget_show on toplevel=%p",
          static_cast<void*>(top));
  gtk_widget_show(top);
  MVD_LOG("first_frame_cb  calling gtk_widget_grab_focus on view=%p",
          static_cast<void*>(view));
  gtk_widget_grab_focus(GTK_WIDGET(view));
  MVD_LOG("first_frame_cb  DONE  view_id=%" G_GINT64_FORMAT, view_id);
}

static gchar* resolve_flutter_bundle_root(void) {
  g_autofree gchar* self = g_file_read_link("/proc/self/exe", nullptr);
  if (!self) {
    return nullptr;
  }
  g_autofree gchar* exe_dir = g_path_get_dirname(self);
  {
    g_autofree gchar* test =
        g_build_filename(exe_dir, "data", "flutter_assets", nullptr);
    if (g_file_test(test, G_FILE_TEST_IS_DIR)) {
      return g_strdup(exe_dir);
    }
  }
  {
    g_autofree gchar* peer =
        g_build_filename(exe_dir, "..", "bundle", nullptr);
    g_autofree gchar* canon = g_canonicalize_filename(peer, nullptr);
    if (!canon) {
      return nullptr;
    }
    g_autofree gchar* test =
        g_build_filename(canon, "data", "flutter_assets", nullptr);
    if (g_file_test(test, G_FILE_TEST_IS_DIR)) {
      return g_strdup(canon);
    }
  }
  return nullptr;
}

static void create_secondary_window(const MvdCreateWindowRequest* request) {
  MVD_LOG("create_secondary_window  START  g_app=%p  g_shared_engine=%p"
          "  request=%p",
          static_cast<void*>(g_app),
          static_cast<void*>(g_shared_engine),
          static_cast<const void*>(request));
  if (!g_app || !g_shared_engine || !request) {
    MVD_LOG("create_secondary_window  ABORT: missing g_app=%p"
            " g_shared_engine=%p request=%p",
            static_cast<void*>(g_app),
            static_cast<void*>(g_shared_engine),
            static_cast<const void*>(request));
    return;
  }

  const char* title =
      (request->title && request->title[0]) ? request->title : g_default_title;

  MVD_LOG("create_secondary_window  token=%" G_GINT64_FORMAT
          "  title='%s'  size=%.0fx%.0f"
          "  has_position=%d  pos=(%.0f,%.0f)"
          "  title_bar_style='%s'",
          request->token, title, request->width, request->height,
          static_cast<int>(request->has_position),
          request->pos_x, request->pos_y,
          request->title_bar_style ? request->title_bar_style : "");

  MVD_LOG("create_secondary_window  calling gtk_application_window_new"
          "  g_app=%p", static_cast<void*>(g_app));
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(g_app)));
  MVD_LOG("create_secondary_window  GtkWindow created: window=%p",
          static_cast<void*>(window));

  MvdLinuxWindow::DecorateToplevel(window, title);
  gtk_window_set_default_size(window, static_cast<int>(request->width),
                              static_cast<int>(request->height));
  MVD_LOG("create_secondary_window  default_size=%.0fx%.0f",
          request->width, request->height);

  if (request->has_position) {
    MVD_LOG("create_secondary_window  moving window to (%.0f,%.0f)",
            request->pos_x, request->pos_y);
    gtk_window_move(window, static_cast<int>(request->pos_x),
                    static_cast<int>(request->pos_y));
  }

  MVD_LOG("create_secondary_window  calling fl_view_new_for_engine"
          "  engine=%p", static_cast<void*>(g_shared_engine));
  FlView* view = fl_view_new_for_engine(g_shared_engine);
  MVD_LOG("create_secondary_window  FlView created: view=%p",
          static_cast<void*>(view));

  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);

  MVD_LOG("create_secondary_window  calling gtk_widget_show on view=%p",
          static_cast<void*>(view));
  gtk_widget_show(GTK_WIDGET(view));

  MVD_LOG("create_secondary_window  calling gtk_container_add"
          "  window=%p  view=%p",
          static_cast<void*>(window), static_cast<void*>(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  MVD_LOG("create_secondary_window  connecting first-frame signal"
          "  view=%p", static_cast<void*>(view));
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           GINT_TO_POINTER(0));

  MVD_LOG("create_secondary_window  calling gtk_widget_realize  view=%p",
          static_cast<void*>(view));
  gtk_widget_realize(GTK_WIDGET(view));
  MVD_LOG("create_secondary_window  gtk_widget_realize returned  view=%p",
          static_cast<void*>(view));

  MVD_LOG("create_secondary_window  calling mvd_linux_complete_secondary_window"
          "  token=%" G_GINT64_FORMAT "  window=%p  view=%p",
          request->token, static_cast<void*>(window),
          static_cast<void*>(view));
  mvd_linux_complete_secondary_window(window, view, request->token);
  MVD_LOG("create_secondary_window  END  token=%" G_GINT64_FORMAT
          "  (window will be shown from first_frame_cb)", request->token);
  // Shown from first_frame_cb after the first Flutter frame is rendered.
}

static void window_created_callback(const MvdCreateWindowRequest* request) {
  MVD_LOG("window_created_callback  RECEIVED  token=%" G_GINT64_FORMAT
          "  size=%.0fx%.0f  title='%s'"
          "  title_bar_style='%s'  has_position=%d  pos=(%.0f,%.0f)",
          request->token, request->width, request->height,
          request->title ? request->title : "",
          request->title_bar_style ? request->title_bar_style : "",
          static_cast<int>(request->has_position),
          request->pos_x, request->pos_y);

  // Copy strings before the async GLib callback runs.
  struct Ctx {
    MvdCreateWindowRequest request;
    std::string title;
    std::string title_bar_style;
  };
  auto* ctx = new Ctx;
  ctx->title = request->title ? request->title : "";
  ctx->title_bar_style = request->title_bar_style ? request->title_bar_style : "";
  ctx->request = *request;
  ctx->request.title = ctx->title.c_str();
  ctx->request.title_bar_style = ctx->title_bar_style.c_str();
  MVD_LOG("window_created_callback  marshaling to main thread via"
          " g_main_context_invoke  token=%" G_GINT64_FORMAT, request->token);
  g_main_context_invoke(
      nullptr,
      [](gpointer data) -> gboolean {
        std::unique_ptr<Ctx> c(static_cast<Ctx*>(data));
        MVD_LOG("window_created_callback  main-thread callback"
                "  token=%" G_GINT64_FORMAT, c->request.token);
        create_secondary_window(&c->request);
        return G_SOURCE_REMOVE;
      },
      ctx);
  MVD_LOG("window_created_callback  g_main_context_invoke dispatched"
          "  token=%" G_GINT64_FORMAT, request->token);
}

}  // namespace

extern "C" {

void multiview_desktop_linux_runner_install(GtkApplication* application) {
  MVD_LOG("runner_install  START  application=%p",
          static_cast<void*>(application));
  g_app = application;
  mvd_linux_set_window_created_callback(window_created_callback);

  // X11: install custom error handler.
  // Must be done AFTER GDK is initialized (which happens before activate),
  // so that we correctly chain to GDK's handler for non-GLX errors.
#ifdef GDK_WINDOWING_X11
  GdkDisplay* gdk_display = gdk_display_get_default();
  if (GDK_IS_X11_DISPLAY(gdk_display)) {
    Display* xdisplay = GDK_DISPLAY_XDISPLAY(gdk_display);
    int event_base = 0;
    int error_base = 0;
    if (XQueryExtension(xdisplay, "GLX",
                        &g_glx_opcode, &event_base, &error_base)) {
      g_glx_error_base = error_base;
      MVD_LOG("runner_install  X11: GLX found  opcode=%d"
              "  event_base=%d  error_base=%d"
              "  (GLXBadContext=%d GLXBadDrawable=%d)",
              g_glx_opcode, event_base, error_base,
              error_base + 0, error_base + 2);
    } else {
      MVD_LOG("runner_install  X11: GLX extension NOT found"
              "  (X11 error suppression will not be active)");
      g_glx_opcode = -1;
      g_glx_error_base = -1;
    }
    // XSetErrorHandler is process-wide: replace GDK's handler with ours,
    // saving the previous one so we can chain non-GLX errors to it.
    g_prev_x_error_handler = XSetErrorHandler(mvd_x11_error_handler);
    MVD_LOG("runner_install  X11: installed mvd_x11_error_handler"
            "  prev_handler=%p",
            reinterpret_cast<void*>(
                reinterpret_cast<uintptr_t>(g_prev_x_error_handler)));
  } else {
    MVD_LOG("runner_install  not X11 display, skipping error handler install");
  }
#else
  MVD_LOG("runner_install  GDK_WINDOWING_X11 not defined, skipping");
#endif

  MVD_LOG("runner_install  DONE  g_app=%p  window_created_callback registered",
          static_cast<void*>(g_app));
}

void multiview_desktop_linux_runner_prepare_dart_project(FlDartProject* project) {
  MVD_LOG("prepare_dart_project  START  project=%p",
          static_cast<void*>(project));
  g_return_if_fail(FL_IS_DART_PROJECT(project));
  g_autofree gchar* root = resolve_flutter_bundle_root();
  if (!root) {
    MVD_LOG("prepare_dart_project  WARN: could not resolve flutter bundle root"
            " (will use defaults)");
    return;
  }
  MVD_LOG("prepare_dart_project  bundle_root='%s'", root);
  g_autofree gchar* assets =
      g_build_filename(root, "data", "flutter_assets", nullptr);
  g_autofree gchar* icu =
      g_build_filename(root, "data", "icudtl.dat", nullptr);
  MVD_LOG("prepare_dart_project  assets='%s'", assets);
  MVD_LOG("prepare_dart_project  icu='%s'", icu);
  fl_dart_project_set_assets_path(project, g_strdup(assets));
  fl_dart_project_set_icu_data_path(project, g_strdup(icu));
  g_autofree gchar* aot = g_build_filename(root, "lib", "libapp.so", nullptr);
  if (g_file_test(aot, G_FILE_TEST_IS_REGULAR)) {
    MVD_LOG("prepare_dart_project  aot='%s'  (file exists)", aot);
    fl_dart_project_set_aot_library_path(project, g_strdup(aot));
  } else {
    MVD_LOG("prepare_dart_project  aot='%s'  (NOT found, running JIT)",
            aot);
    fl_dart_project_set_aot_library_path(project, nullptr);
  }
  MVD_LOG("prepare_dart_project  DONE");
}

void multiview_desktop_linux_runner_register_primary(GtkWindow* window,
                                                     FlView* view) {
  g_return_if_fail(GTK_IS_WINDOW(window));
  g_return_if_fail(FL_IS_VIEW(view));
  MVD_LOG("runner_register_primary  START  window=%p  view=%p",
          static_cast<void*>(window), static_cast<void*>(view));
  g_shared_engine = fl_view_get_engine(view);
  const int64_t view_id = fl_view_get_id(view);
  MVD_LOG("runner_register_primary  g_shared_engine=%p  view_id=%"
          G_GINT64_FORMAT, static_cast<void*>(g_shared_engine), view_id);
  mvd_linux_register_primary(window, view);
  MVD_LOG("runner_register_primary  DONE  primary window=%p  view=%p"
          "  view_id=%" G_GINT64_FORMAT,
          static_cast<void*>(window), static_cast<void*>(view), view_id);
}

void multiview_desktop_linux_runner_set_default_title(const char* title) {
  if (title && title[0]) {
    g_default_title = title;
  }
}

}  // extern "C"
