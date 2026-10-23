#include "../mvd_linux_window.h"
#include <gdk/gdkx.h>
#include <gtk/gtk.h>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>
#include <cstdio>
#include <cstdlib>
#include <string>

static void Drain(int milliseconds) {
  const gint64 end = g_get_monotonic_time() + milliseconds * 1000;
  do {
    while (g_main_context_iteration(nullptr, FALSE)) {}
    g_usleep(1000);
  } while (g_get_monotonic_time() < end);
}
static bool Active(GtkWindow* window) {
  for (int i = 0; i < 100; ++i) {
    Drain(10);
    if (gtk_window_is_active(window)) return true;
  }
  return false;
}
static void Command(const std::string& command) {
  gint status = 0;
  GError* error = nullptr;
  if (!g_spawn_command_line_sync(command.c_str(), nullptr, nullptr, &status, &error) || status) {
    g_error("Native focus test command failed: %s", error ? error->message : command.c_str());
  }
}
int main(int argc, char** argv) {
  gtk_init(&argc, &argv);
  if (!GDK_IS_X11_DISPLAY(gdk_display_get_default())) return 77;
  g_autofree gchar* xdotool = g_find_program_in_path("xdotool");
  if (!xdotool) return 77;
  GtkWindow* window = GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL));
  gtk_window_set_title(window, argc > 1 ? "Foreign native focus target" : "Native activation contract");
  gtk_window_set_default_size(window, 320, 180);
  gtk_container_add(GTK_CONTAINER(window), gtk_entry_new());
  gtk_widget_show_all(GTK_WIDGET(window));
  if (argc > 1) {
    g_print("%lu\n", GDK_WINDOW_XID(gtk_widget_get_window(GTK_WIDGET(window))));
    fflush(stdout);
    gtk_main();
    return 0;
  }
  GPid child = 0;
  gint child_stdout = -1;
  gchar* child_args[] = {argv[0], const_cast<char*>("--target"), nullptr};
  if (!g_spawn_async_with_pipes(nullptr, child_args, nullptr, G_SPAWN_DO_NOT_REAP_CHILD,
      nullptr, nullptr, &child, nullptr, &child_stdout, nullptr, nullptr)) return 2;
  FILE* pipe = fdopen(child_stdout, "r");
  unsigned long target = 0;
  if (fscanf(pipe, "%lu", &target) != 1) {
    fclose(pipe);
    kill(child, SIGTERM);
    waitpid(child, nullptr, 0);
    g_spawn_close_pid(child);
    return 2;
  }
  fclose(pipe);
  Drain(300);
  const unsigned long own = GDK_WINDOW_XID(gtk_widget_get_window(GTK_WIDGET(window)));
  auto foreign = [&]() {
    Command("xdotool windowactivate --sync " + std::to_string(target));
    Command("xdotool key --clearmodifiers t");
    Drain(150);
  };
  MvdLinuxWindow managed;
  managed.window = window;
  managed.focus_on_show = true;
  // Seed a real, then deliberately stale, GDK user timestamp in this process.
  Command("xdotool windowactivate --sync " + std::to_string(own));
  Command("xdotool key --clearmodifiers p");
  Drain(150);
  foreign();
  managed.Focus();
  bool activated = Active(window);
  g_print("Explicit activation after foreign input: %s\n", activated ? "PASS" : "FAIL");
  // A previously interactive utility must remain passive after hide/show too.
  managed.focus_on_show = false;
  managed.is_pomo = true;
  g_object_set_data(G_OBJECT(window), "mvd-pomo-role", const_cast<char*>("companion"));
  gtk_window_set_focus_on_map(window, FALSE);
  gtk_widget_hide(GTK_WIDGET(window));
  foreign();
  managed.Show();
  Drain(400);
  bool passive = !gtk_window_is_active(window) && !gtk_window_get_accept_focus(window);
  gtk_window_set_accept_focus(window, TRUE);
  g_print("Passive re-show preserves foreign focus: %s\n", passive ? "PASS" : "FAIL");
  managed.Minimize();
  Drain(200);
  foreign();
  managed.Restore();
  Drain(400);
  bool passive_restored = !gtk_window_is_active(window) && !gtk_window_get_accept_focus(window);
  g_print("Passive restore preserves foreign focus: %s\n", passive_restored ? "PASS" : "FAIL");
  gtk_window_set_accept_focus(window, TRUE);
  managed.focus_on_show = true;
  managed.Minimize();
  Drain(200);
  foreign();
  managed.Restore();
  bool restored = Active(window);
  g_print("Explicit restore after foreign input: %s\n", restored ? "PASS" : "FAIL");
  managed.window = nullptr;
  gtk_widget_destroy(GTK_WIDGET(window));
  kill(child, SIGTERM);
  waitpid(child, nullptr, 0);
  g_spawn_close_pid(child);
  return activated && passive && passive_restored && restored ? 0 : 1;
}
