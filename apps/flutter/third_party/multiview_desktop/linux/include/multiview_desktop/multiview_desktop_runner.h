#ifndef MULTIVIEW_DESKTOP_RUNNER_H_
#define MULTIVIEW_DESKTOP_RUNNER_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <glib.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

/// Call once at the start of GApplication::activate, before creating the primary FlView.
/// Hooks Dart createWindow to open additional GTK windows.
FLUTTER_PLUGIN_EXPORT void multiview_desktop_linux_runner_install(
    GtkApplication* application);

/// Fixes asset, ICU, and AOT paths when launched from the build directory.
/// Call right after fl_dart_project_new in the runner template.
FLUTTER_PLUGIN_EXPORT void multiview_desktop_linux_runner_prepare_dart_project(
    FlDartProject* project);

/// Call after fl_register_plugins on the primary FlView.
FLUTTER_PLUGIN_EXPORT void multiview_desktop_linux_runner_register_primary(
    GtkWindow* window,
    FlView* view);

/// Default title for secondary windows created from Dart.
FLUTTER_PLUGIN_EXPORT void multiview_desktop_linux_runner_set_default_title(
    const char* title);

G_END_DECLS

#endif  // MULTIVIEW_DESKTOP_RUNNER_H_
