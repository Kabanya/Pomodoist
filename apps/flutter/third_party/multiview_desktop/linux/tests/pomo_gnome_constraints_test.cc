#include "../mvd_linux_window.h"
#include <cassert>
// A tagged object exercises the policy before any GTK call. Reaching GTK with
// this object is a fatal critical, catching accidentally applied native hints.
int main() {
  g_log_set_always_fatal(static_cast<GLogLevelFlags>(G_LOG_FATAL_MASK | G_LOG_LEVEL_CRITICAL));
  g_autoptr(GObject) tagged = G_OBJECT(g_object_new(G_TYPE_OBJECT, nullptr));
  g_object_set_data(tagged, "mvd-gnome-token", const_cast<char*>("owned-token"));
  MvdLinuxWindow window;
  window.window = reinterpret_cast<GtkWindow*>(tagged);
  window.SetMinimumSize(320, 256);
  window.SetMaximumSize(320, 256);
  window.SetResizable(false);
  assert(!window.IsResizable());
  assert(!window.size_locked_by_non_resizable);
  window.ReapplyGeometryHints();
  window.SetResizable(true);
  assert(window.IsResizable());
}
