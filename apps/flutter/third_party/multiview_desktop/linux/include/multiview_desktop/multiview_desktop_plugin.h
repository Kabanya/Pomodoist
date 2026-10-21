#ifndef FLUTTER_PLUGIN_MULTIVIEW_DESKTOP_PLUGIN_H_
#define FLUTTER_PLUGIN_MULTIVIEW_DESKTOP_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

#include <glib.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

FLUTTER_PLUGIN_EXPORT void multiview_desktop_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_MULTIVIEW_DESKTOP_PLUGIN_H_
