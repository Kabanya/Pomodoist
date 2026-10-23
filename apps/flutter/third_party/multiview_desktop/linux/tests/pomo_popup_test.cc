#include "../mvd_linux_pomo_popup.h"
#include <gtk-layer-shell.h>
#include <glib-unix.h>
#include <cstring>
#include <signal.h>

namespace {
GtkWindow* panel;
GtkWindow* parent_window;
GtkWidget* entry;
bool legacy = false;
bool check_bounds = false;
int closes = 0;
void Hide() {
#ifdef POMO_POPUP_BASELINE
  gtk_widget_hide(GTK_WIDGET(panel));
#else
  if (legacy) gtk_widget_hide(GTK_WIDGET(panel));
  else mvd_linux_pomo_popup_hide(panel);
#endif
}
gboolean Close(GtkWidget*, GdkEvent*, gpointer) {
  ++closes;
  g_print("CLOSE %d\n", closes);
  Hide();
  return TRUE;
}
void Open(GtkButton*, gpointer) {
  GdkEvent* event = gtk_get_current_event();
#ifdef POMO_POPUP_BASELINE
  gtk_widget_show_all(GTK_WIDGET(panel));
  gtk_window_present(panel);
#else
  if (legacy) {
    gtk_widget_show_all(GTK_WIDGET(panel));
    gtk_window_present(panel);
  } else {
    g_assert_true(mvd_linux_pomo_popup_show(panel, event));
  }
#endif
#ifndef POMO_POPUP_BASELINE
  GdkRectangle actual{};
  if (!legacy && mvd_linux_pomo_popup_bounds(panel, &actual))
    g_print("BOUNDS %d %d %d %d\n", actual.x, actual.y, actual.width, actual.height);
#endif
  gtk_widget_grab_focus(entry);
  if (event) gdk_event_free(event);
  g_print("OPEN\n");
}
gboolean ToggleParent(gpointer) {
  if (gtk_widget_get_visible(GTK_WIDGET(parent_window)))
    gtk_widget_hide(GTK_WIDGET(parent_window));
  else gtk_widget_show_all(GTK_WIDGET(parent_window));
  return G_SOURCE_CONTINUE;
}
gboolean DestroyParent(gpointer) {
#ifndef POMO_POPUP_BASELINE
  if (!legacy) {
    g_object_ref(panel);
    gtk_widget_destroy(GTK_WIDGET(parent_window));
    g_assert_false(gtk_widget_get_visible(GTK_WIDGET(panel)));
    g_assert_true(gtk_grab_get_current() != GTK_WIDGET(panel));
    g_assert_null(gtk_window_get_focus(panel));
    GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(panel));
    GdkSeat* seat = gdk_display_get_default_seat(display);
    g_assert_false(gdk_display_device_is_grabbed(display, gdk_seat_get_keyboard(seat)));
    g_assert_false(gdk_display_device_is_grabbed(display, gdk_seat_get_pointer(seat)));
    g_object_unref(panel);
    g_print("PARENT_DESTROY_RELEASE_PASS\n");
  }
#endif
  gtk_main_quit();
  return G_SOURCE_REMOVE;
}
[[maybe_unused]] void CaptureBeforeConsumedChild() {
  GtkWidget* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  GtkWidget* box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  GtkWidget* child = gtk_event_box_new();
  gtk_event_box_set_visible_window(GTK_EVENT_BOX(child), TRUE);
  gtk_container_add(GTK_CONTAINER(window), box);
  gtk_container_add(GTK_CONTAINER(box), child);
  gtk_container_add(GTK_CONTAINER(child), gtk_label_new("Consumed pointer child"));
  gtk_widget_set_size_request(child, 200, 80);
  gtk_widget_add_events(child, GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK);
  int observed = 0, consumed = 0;
  g_signal_connect(child, "button-press-event", G_CALLBACK(+[](GtkWidget*, GdkEvent*, gpointer data) -> gboolean {
    ++*static_cast<int*>(data); return TRUE;
  }), &consumed);
#ifdef POMO_CAPTURE_BASELINE
  g_signal_connect(window, "event", G_CALLBACK(+[](GtkWidget*, GdkEvent* event, gpointer data) -> gboolean {
    if (event->type == GDK_BUTTON_PRESS) ++*static_cast<int*>(data);
    return FALSE;
  }), &observed);
#else
#ifndef POMO_POPUP_BASELINE
  mvd_linux_pomo_popup_watch(GTK_WINDOW(window), +[](GtkWindow*, const GdkEvent* event, gpointer data) {
    if (event->type == GDK_BUTTON_PRESS) ++*static_cast<int*>(data);
  }, &observed);
  // Reinstallation replaces the observer rather than adding another controller.
  mvd_linux_pomo_popup_watch(GTK_WINDOW(window), +[](GtkWindow*, const GdkEvent* event, gpointer data) {
    if (event->type == GDK_BUTTON_PRESS) ++*static_cast<int*>(data);
  }, &observed);
#endif
#endif
  gtk_widget_show_all(window);
  while (g_main_context_pending(nullptr)) g_main_context_iteration(nullptr, FALSE);
  GdkEvent* event = gdk_event_new(GDK_BUTTON_PRESS);
  event->button.window = GDK_WINDOW(g_object_ref(gtk_widget_get_window(child)));
  event->button.time = GDK_CURRENT_TIME;
  event->button.x = event->button.y = 10;
  event->button.button = GDK_BUTTON_PRIMARY;
  gdk_event_set_device(event, gdk_seat_get_pointer(gdk_display_get_default_seat(gtk_widget_get_display(window))));
  gtk_main_do_event(event);
  gdk_event_free(event);
  g_assert_cmpint(consumed, ==, 1);
  g_assert_cmpint(observed, ==, 1);
  gtk_widget_destroy(window);
}
[[maybe_unused]] void ConsumedPopupOutsideClick([[maybe_unused]] bool escape = false) {
#ifndef POMO_POPUP_BASELINE
  GtkWindow* parent = GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL));
  GtkWindow* popup = mvd_linux_pomo_popup_new(parent);
  GtkWidget* child = gtk_event_box_new();
  gtk_widget_add_events(child, GDK_BUTTON_PRESS_MASK | GDK_KEY_PRESS_MASK);
  gtk_widget_set_can_focus(child, TRUE);
  gtk_widget_set_size_request(child, 160, 80);
  gtk_container_add(GTK_CONTAINER(popup), child);
  int consumed = 0, closed = 0;
  g_signal_connect(child, "button-press-event", G_CALLBACK(+[](GtkWidget*, GdkEvent*, gpointer data) -> gboolean {
    ++*static_cast<int*>(data); return TRUE;
  }), &consumed);
  g_signal_connect(child, "key-press-event", G_CALLBACK(+[](GtkWidget*, GdkEvent*, gpointer data) -> gboolean {
    ++*static_cast<int*>(data); return TRUE;
  }), &consumed);
  g_signal_connect(popup, "delete-event", G_CALLBACK(+[](GtkWidget*, GdkEvent*, gpointer data) -> gboolean {
    ++*static_cast<int*>(data); return TRUE;
  }), &closed);
  gtk_widget_show_all(GTK_WIDGET(popup));
  while (g_main_context_pending(nullptr)) g_main_context_iteration(nullptr, FALSE);
  gtk_widget_grab_focus(child);
  GdkEvent* event = gdk_event_new(escape ? GDK_KEY_PRESS : GDK_BUTTON_PRESS);
  event->any.window = GDK_WINDOW(g_object_ref(gtk_widget_get_window(child)));
  GdkSeat* seat = gdk_display_get_default_seat(gtk_widget_get_display(child));
  if (escape) {
    event->key.keyval = GDK_KEY_Escape;
    event->key.hardware_keycode = 9;
    gdk_event_set_device(event, gdk_seat_get_keyboard(seat));
  } else {
    event->button.x = -10; event->button.y = 10;
    event->button.button = GDK_BUTTON_PRIMARY;
    gdk_event_set_device(event, gdk_seat_get_pointer(seat));
  }
  gtk_main_do_event(event);
  gdk_event_free(event);
  g_assert_cmpint(closed, ==, 1);
  g_assert_false(gtk_widget_get_visible(GTK_WIDGET(popup)));
  // The capture observer must not claim or deliver a duplicate close.
  g_assert_cmpint(consumed, <=, 1);
  gtk_widget_destroy(GTK_WIDGET(parent));
#endif
}
gboolean BreakGrab(gpointer) {
  GdkEvent* event = gdk_event_new(GDK_GRAB_BROKEN);
  event->grab_broken.window = GDK_WINDOW(g_object_ref(gtk_widget_get_window(GTK_WIDGET(panel))));
  event->grab_broken.keyboard = TRUE;
  event->grab_broken.implicit = FALSE;
  gtk_widget_event(GTK_WIDGET(panel), event);
  gdk_event_free(event);
  return G_SOURCE_CONTINUE;
}
gboolean VerifyReleased(gpointer) {
#ifndef POMO_POPUP_BASELINE
  if (!legacy) {
    g_assert_false(gtk_widget_get_visible(GTK_WIDGET(panel)));
    g_assert_false(gtk_widget_has_grab(GTK_WIDGET(panel)));
    g_assert_true(gtk_grab_get_current() != GTK_WIDGET(panel));
    g_assert_null(gtk_window_get_focus(panel));
    GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(panel));
    GdkSeat* seat = gdk_display_get_default_seat(display);
    g_assert_false(gdk_display_device_is_grabbed(display, gdk_seat_get_keyboard(seat)));
    g_assert_false(gdk_display_device_is_grabbed(display, gdk_seat_get_pointer(seat)));
    g_print("GRAB_RELEASE_PASS\n");
  }
#endif
  return G_SOURCE_CONTINUE;
}
gboolean Verify(gpointer) {
  g_assert_cmpstr(gtk_entry_get_text(GTK_ENTRY(entry)), ==, "probe");
#ifndef POMO_POPUP_BASELINE
  if (check_bounds && !legacy) {
    const GdkRectangle source{400, 180, 240, 40};
    const GdkRectangle wanted{500, 600, 320, 100};
    mvd_linux_pomo_popup_move(panel, &source, &wanted);
    GdkRectangle actual{}, native{};
    gdk_window_get_geometry(gtk_widget_get_window(GTK_WIDGET(panel)),
        &native.x, &native.y, &native.width, &native.height);
    g_assert_true(mvd_linux_pomo_popup_bounds(panel, &actual));
    g_assert_cmpint(actual.x, ==, native.x + 400);
    g_assert_cmpint(actual.y, ==, native.y + 180);
    g_assert_cmpint(actual.width, ==, native.width);
    g_assert_cmpint(actual.height, ==, native.height);
    g_print("MAPPED_BOUNDS_PASS\n");
  }
#endif
  g_print("INPUT_PASS\n");
  return G_SOURCE_CONTINUE;
}
}  // namespace

int main(int argc, char** argv) {
  gtk_init(&argc, &argv);
  const bool unit = argc > 1 && std::strcmp(argv[1], "--unit") == 0;
  GtkWindow* parent = GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL));
  parent_window = parent;
  if (unit) {
#ifndef POMO_POPUP_BASELINE
    CaptureBeforeConsumedChild();
    ConsumedPopupOutsideClick();
    ConsumedPopupOutsideClick(true);
#endif
#ifdef POMO_POPUP_BASELINE
    panel = GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL));
#else
    g_assert_null(mvd_linux_pomo_popup_new(nullptr));
    panel = mvd_linux_pomo_popup_new(parent);
    g_assert_true(mvd_linux_pomo_popup_is(panel));
    g_assert_false(mvd_linux_pomo_popup_is(parent));
#endif
    g_assert_cmpint(gtk_window_get_window_type(panel), ==, GTK_WINDOW_POPUP);
#ifndef POMO_POPUP_BASELINE
    const GdkRectangle source{400, 180, 200, 150};
    const GdkRectangle desired{60, 300, 320, 256};
    mvd_linux_pomo_popup_move(panel, &source, &desired);
    GdkRectangle actual{};
    g_assert_true(mvd_linux_pomo_popup_bounds(panel, &actual));
    g_assert_cmpint(actual.x, ==, 60);
    g_assert_cmpint(actual.y, ==, 300);
    g_assert_cmpint(actual.width, ==, 320);
    g_assert_cmpint(actual.height, ==, 256);
    gtk_widget_realize(GTK_WIDGET(panel));
    const GdkRectangle configured{10, 20, 250, 120};
    g_signal_emit_by_name(gtk_widget_get_window(GTK_WIDGET(panel)),
        "moved-to-rect", nullptr, &configured, FALSE, FALSE);
    g_assert_true(mvd_linux_pomo_popup_bounds(panel, &actual));
    g_assert_cmpint(actual.x, ==, 410);
    g_assert_cmpint(actual.y, ==, 200);
    g_assert_cmpint(actual.width, ==, 250);
    g_assert_cmpint(actual.height, ==, 120);
    g_assert_false(mvd_linux_pomo_popup_show(panel, nullptr));
    g_assert_false(gtk_widget_get_visible(GTK_WIDGET(panel)));
    mvd_linux_pomo_popup_hide(panel);
    mvd_linux_pomo_popup_hide(panel);
#endif
    gtk_widget_destroy(GTK_WIDGET(parent));
    g_print("POPUP_UNIT_PASS\n");
    return 0;
  }
  legacy = argc > 1 && std::strcmp(argv[1], "--legacy") == 0;
  check_bounds = argc > 1 && std::strcmp(argv[1], "--constrained") == 0;
  GtkWidget* target = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  GtkWidget* target_entry = gtk_entry_new();
  gtk_window_set_title(GTK_WINDOW(target), "Popup regression target");
  gtk_container_add(GTK_CONTAINER(target), target_entry);
  gtk_window_maximize(GTK_WINDOW(target));
  gtk_widget_show_all(target);
  gtk_layer_init_for_window(parent);
  gtk_layer_set_namespace(parent, "pomo-popup-regression");
  gtk_layer_set_layer(parent, GTK_LAYER_SHELL_LAYER_TOP);
  gtk_layer_set_keyboard_mode(parent, GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND);
  gtk_layer_set_anchor(parent, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
  gtk_layer_set_anchor(parent, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
  gtk_layer_set_margin(parent, GTK_LAYER_SHELL_EDGE_LEFT, 400);
  gtk_layer_set_margin(parent, GTK_LAYER_SHELL_EDGE_TOP, 180);
  GtkWidget* button = gtk_button_new_with_label("Open native popup regression");
  gtk_widget_set_size_request(button, 240, 40);
  gtk_container_add(GTK_CONTAINER(parent), button);
  gtk_widget_show_all(GTK_WIDGET(parent));
#ifdef POMO_POPUP_BASELINE
  panel = GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL));
#else
  panel = legacy ? GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL))
                 : mvd_linux_pomo_popup_new(parent);
#endif
  if (legacy) {
    gtk_layer_init_for_window(panel);
    gtk_layer_set_keyboard_mode(panel, GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND);
    gtk_layer_set_anchor(panel, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    gtk_layer_set_anchor(panel, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
    gtk_layer_set_margin(panel, GTK_LAYER_SHELL_EDGE_LEFT, 60);
    gtk_layer_set_margin(panel, GTK_LAYER_SHELL_EDGE_TOP, 300);
  }
#ifndef POMO_POPUP_BASELINE
  else {
    const GdkRectangle source{400, 180, 240, 40};
    const GdkRectangle desired = argc > 1 && std::strcmp(argv[1], "--constrained") == 0
        ? GdkRectangle{-60, 760, 320, 100} : GdkRectangle{60, 300, 320, 100};
    mvd_linux_pomo_popup_move(panel, &source, &desired);
  }
#endif
  entry = gtk_entry_new();
  gtk_widget_set_size_request(entry, 320, 100);
  gtk_container_add(GTK_CONTAINER(panel), entry);
  g_signal_connect(entry, "changed", G_CALLBACK(+[](GtkEntry* item, gpointer) {
    g_print("POPUP_TEXT %s\n", gtk_entry_get_text(item));
  }), nullptr);
  g_signal_connect(target_entry, "changed", G_CALLBACK(+[](GtkEntry* item, gpointer) {
    g_print("TARGET_TEXT %s\n", gtk_entry_get_text(item));
  }), nullptr);
  g_signal_connect(panel, "delete-event", G_CALLBACK(Close), nullptr);
  g_signal_connect(button, "clicked", G_CALLBACK(Open), nullptr);
  g_unix_signal_add(SIGUSR1, Verify, nullptr);
  g_unix_signal_add(SIGUSR2, VerifyReleased, nullptr);
  g_unix_signal_add(SIGHUP, ToggleParent, nullptr);
  g_unix_signal_add(SIGTERM, DestroyParent, nullptr);
  g_unix_signal_add(SIGWINCH, BreakGrab, nullptr);
  g_print("READY\n");
  gtk_main();
}
