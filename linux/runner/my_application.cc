#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <X11/keysym.h>
#include <gdk/gdkx.h>
#endif
#include <multiview_desktop/multiview_desktop_runner.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char **dart_entrypoint_arguments;
  FlMethodChannel *quick_add_channel;
  gboolean quick_add_enabled;
  gint64 quick_add_key_code;
  gchar *quick_add_key_label;
#ifdef GDK_WINDOWING_X11
  GdkDisplay *quick_add_gdk_display;
  Display *quick_add_x_display;
  Window quick_add_root;
  guint quick_add_keycode;
  guint quick_add_modifiers;
  gboolean quick_add_filter_installed;
#endif
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static FlMethodResponse *quick_add_error(const gchar *code,
                                         const gchar *message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message, nullptr));
}

#ifdef GDK_WINDOWING_X11
static KeySym quick_add_keysym(const gchar *label) {
  if (g_strcmp0(label, "Space") == 0)
    return XK_space;
  if (g_strcmp0(label, "Enter") == 0)
    return XK_Return;
  if (g_strcmp0(label, "Tab") == 0)
    return XK_Tab;
  if (g_strcmp0(label, "Delete") == 0)
    return XK_Delete;
  if (g_strcmp0(label, "Backspace") == 0)
    return XK_BackSpace;
  if (g_strcmp0(label, "Escape") == 0 || g_strcmp0(label, "Esc") == 0)
    return XK_Escape;
  if (g_strcmp0(label, "Home") == 0)
    return XK_Home;
  if (g_strcmp0(label, "End") == 0)
    return XK_End;
  if (g_strcmp0(label, "Page Up") == 0)
    return XK_Page_Up;
  if (g_strcmp0(label, "Page Down") == 0)
    return XK_Page_Down;
  if (g_strcmp0(label, "Arrow Left") == 0)
    return XK_Left;
  if (g_strcmp0(label, "Arrow Right") == 0)
    return XK_Right;
  if (g_strcmp0(label, "Arrow Up") == 0)
    return XK_Up;
  if (g_strcmp0(label, "Arrow Down") == 0)
    return XK_Down;
  if (label != nullptr && label[0] != '\0' && label[1] == '\0') {
    gchar key[2] = {g_ascii_toupper(label[0]), '\0'};
    return XStringToKeysym(key);
  }
  return label == nullptr ? NoSymbol : XStringToKeysym(label);
}

static void change_x11_grab(MyApplication *self, guint keycode, guint modifiers,
                            gboolean grab) {
  const guint ignored_modifiers[] = {0, LockMask, Mod2Mask,
                                     LockMask | Mod2Mask};
  for (guint ignored : ignored_modifiers) {
    if (grab) {
      XGrabKey(self->quick_add_x_display, keycode, modifiers | ignored,
               self->quick_add_root, True, GrabModeAsync, GrabModeAsync);
    } else {
      XUngrabKey(self->quick_add_x_display, keycode, modifiers | ignored,
                 self->quick_add_root);
    }
  }
}

static gboolean register_x11_hotkey(MyApplication *self, guint keycode,
                                    guint modifiers) {
  gdk_x11_display_error_trap_push(self->quick_add_gdk_display);
  change_x11_grab(self, keycode, modifiers, TRUE);
  XSync(self->quick_add_x_display, False);
  return gdk_x11_display_error_trap_pop(self->quick_add_gdk_display) == 0;
}

static GdkFilterReturn quick_add_x11_event_filter(GdkXEvent *xevent, GdkEvent *,
                                                  gpointer data) {
  MyApplication *self = MY_APPLICATION(data);
  XEvent *event = static_cast<XEvent *>(xevent);
  const guint shortcut_mask = ControlMask | Mod1Mask | ShiftMask | Mod4Mask;
  if (self->quick_add_enabled && event->type == KeyPress &&
      event->xkey.keycode == self->quick_add_keycode &&
      (event->xkey.state & shortcut_mask) == self->quick_add_modifiers) {
    fl_method_channel_invoke_method(self->quick_add_channel, "showQuickAdd",
                                    nullptr, nullptr, nullptr, nullptr);
  }
  return GDK_FILTER_CONTINUE;
}
#endif

static gboolean set_quick_add_enabled(MyApplication *self, gboolean enabled) {
  if (enabled == self->quick_add_enabled)
    return TRUE;
#ifdef GDK_WINDOWING_X11
  if (self->quick_add_x_display != nullptr) {
    if (!enabled) {
      change_x11_grab(self, self->quick_add_keycode, self->quick_add_modifiers,
                      FALSE);
      XSync(self->quick_add_x_display, False);
      self->quick_add_enabled = FALSE;
      return TRUE;
    }
    if (!register_x11_hotkey(self, self->quick_add_keycode,
                             self->quick_add_modifiers)) {
      change_x11_grab(self, self->quick_add_keycode, self->quick_add_modifiers,
                      FALSE);
      return FALSE;
    }
    self->quick_add_enabled = TRUE;
    return TRUE;
  }
#endif
  return FALSE;
}

static gboolean read_quick_add_bool(FlValue *map, const gchar *key,
                                    gboolean *value) {
  FlValue *item = fl_value_lookup_string(map, key);
  if (item == nullptr || fl_value_get_type(item) != FL_VALUE_TYPE_BOOL)
    return FALSE;
  *value = fl_value_get_bool(item);
  return TRUE;
}

static void quick_add_method_call_cb(FlMethodChannel *,
                                     FlMethodCall *method_call, gpointer data) {
  MyApplication *self = MY_APPLICATION(data);
  const gchar *method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "getGlobalShortcut") == 0) {
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "keyCode",
                             fl_value_new_int(self->quick_add_key_code));
    fl_value_set_string_take(result, "keyLabel",
                             fl_value_new_string(self->quick_add_key_label));
#ifdef GDK_WINDOWING_X11
    fl_value_set_string_take(
        result, "meta",
        fl_value_new_bool((self->quick_add_modifiers & Mod4Mask) != 0));
    fl_value_set_string_take(
        result, "control",
        fl_value_new_bool((self->quick_add_modifiers & ControlMask) != 0));
    fl_value_set_string_take(
        result, "alt",
        fl_value_new_bool((self->quick_add_modifiers & Mod1Mask) != 0));
    fl_value_set_string_take(
        result, "shift",
        fl_value_new_bool((self->quick_add_modifiers & ShiftMask) != 0));
#else
    fl_value_set_string_take(result, "meta", fl_value_new_bool(FALSE));
    fl_value_set_string_take(result, "control", fl_value_new_bool(TRUE));
    fl_value_set_string_take(result, "alt", fl_value_new_bool(TRUE));
    fl_value_set_string_take(result, "shift", fl_value_new_bool(FALSE));
#endif
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "setGlobalShortcutEnabled") == 0) {
    FlValue *arguments = fl_method_call_get_args(method_call);
    if (arguments == nullptr ||
        fl_value_get_type(arguments) != FL_VALUE_TYPE_BOOL) {
      response = quick_add_error("invalid_arguments", "Expected a boolean.");
    } else if (!set_quick_add_enabled(self, fl_value_get_bool(arguments))) {
      response = quick_add_error(
          "portal_unavailable",
          "Global shortcuts are unavailable on this Wayland session.");
    } else {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else if (g_strcmp0(method, "setGlobalShortcut") == 0) {
    FlValue *arguments = fl_method_call_get_args(method_call);
    FlValue *key_code = arguments == nullptr
                            ? nullptr
                            : fl_value_lookup_string(arguments, "keyCode");
    FlValue *key_label = arguments == nullptr
                             ? nullptr
                             : fl_value_lookup_string(arguments, "keyLabel");
    gboolean meta = FALSE;
    gboolean control = FALSE;
    gboolean alt = FALSE;
    gboolean shift = FALSE;
    if (arguments == nullptr ||
        fl_value_get_type(arguments) != FL_VALUE_TYPE_MAP ||
        key_code == nullptr ||
        fl_value_get_type(key_code) != FL_VALUE_TYPE_INT ||
        key_label == nullptr ||
        fl_value_get_type(key_label) != FL_VALUE_TYPE_STRING ||
        !read_quick_add_bool(arguments, "meta", &meta) ||
        !read_quick_add_bool(arguments, "control", &control) ||
        !read_quick_add_bool(arguments, "alt", &alt) ||
        !read_quick_add_bool(arguments, "shift", &shift)) {
      response = quick_add_error("invalid_shortcut",
                                 "The keyboard shortcut is invalid.");
    } else {
#ifdef GDK_WINDOWING_X11
      const gchar *label = fl_value_get_string(key_label);
      KeySym keysym = quick_add_keysym(label);
      guint keycode = self->quick_add_x_display == nullptr || keysym == NoSymbol
                          ? 0
                          : XKeysymToKeycode(self->quick_add_x_display, keysym);
      guint modifiers = (meta ? Mod4Mask : 0) | (control ? ControlMask : 0) |
                        (alt ? Mod1Mask : 0) | (shift ? ShiftMask : 0);
      if (self->quick_add_x_display == nullptr || keycode == 0 ||
          (modifiers & (Mod4Mask | ControlMask | Mod1Mask)) == 0) {
        response =
            quick_add_error("portal_unavailable",
                            "Global shortcuts require X11 or portal support.");
      } else {
        const guint old_keycode = self->quick_add_keycode;
        const guint old_modifiers = self->quick_add_modifiers;
        if (self->quick_add_enabled) {
          change_x11_grab(self, old_keycode, old_modifiers, FALSE);
          if (!register_x11_hotkey(self, keycode, modifiers)) {
            change_x11_grab(self, keycode, modifiers, FALSE);
            register_x11_hotkey(self, old_keycode, old_modifiers);
            response =
                quick_add_error("shortcut_unavailable",
                                "The global keyboard shortcut is unavailable.");
          }
        }
        if (response == nullptr) {
          self->quick_add_key_code = fl_value_get_int(key_code);
          g_free(self->quick_add_key_label);
          self->quick_add_key_label = g_strdup(label);
          self->quick_add_keycode = keycode;
          self->quick_add_modifiers = modifiers;
          response =
              FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
        }
      }
#else
      response = quick_add_error("portal_unavailable",
                                 "Global shortcuts require portal support.");
#endif
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void configure_quick_add_channel(MyApplication *self, FlView *view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->quick_add_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "pomodoist/quick_add", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->quick_add_channel, quick_add_method_call_cb, self, nullptr);
#ifdef GDK_WINDOWING_X11
  self->quick_add_gdk_display = gdk_display_get_default();
  if (GDK_IS_X11_DISPLAY(self->quick_add_gdk_display)) {
    self->quick_add_x_display =
        gdk_x11_display_get_xdisplay(self->quick_add_gdk_display);
    self->quick_add_root = DefaultRootWindow(self->quick_add_x_display);
    self->quick_add_keycode =
        XKeysymToKeycode(self->quick_add_x_display, XK_space);
    gdk_window_add_filter(nullptr, quick_add_x11_event_filter, self);
    self->quick_add_filter_installed = TRUE;
  }
#endif
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication *self, FlView *view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication *application) {
  MyApplication *self = MY_APPLICATION(application);
  multiview_desktop_linux_runner_install(GTK_APPLICATION(application));

  GList *windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (windows != nullptr) {
    gtk_window_present(GTK_WINDOW(windows->data));
    return;
  }

  GtkWindow *window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen *screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar *wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar *header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Pomodoist");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Pomodoist");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  multiview_desktop_linux_runner_prepare_dart_project(project);
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView *view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  multiview_desktop_linux_runner_register_primary(window, view);
  configure_quick_add_channel(self, view);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication *application,
                                                  gchar ***arguments,
                                                  int *exit_status) {
  MyApplication *self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return FALSE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication *application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication *application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject *object) {
  MyApplication *self = MY_APPLICATION(object);
#ifdef GDK_WINDOWING_X11
  if (self->quick_add_enabled && self->quick_add_x_display != nullptr) {
    change_x11_grab(self, self->quick_add_keycode, self->quick_add_modifiers,
                    FALSE);
  }
  if (self->quick_add_filter_installed) {
    gdk_window_remove_filter(nullptr, quick_add_x11_event_filter, self);
  }
#endif
  g_clear_object(&self->quick_add_channel);
  g_clear_pointer(&self->quick_add_key_label, g_free);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass *klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication *self) {
  self->quick_add_key_code = 32;
  self->quick_add_key_label = g_strdup("Space");
#ifdef GDK_WINDOWING_X11
  self->quick_add_modifiers = ControlMask | Mod1Mask;
#endif
}

MyApplication *my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(
      my_application_get_type(), "application-id", APPLICATION_ID, "flags",
      G_APPLICATION_HANDLES_COMMAND_LINE | G_APPLICATION_HANDLES_OPEN,
      nullptr));
}
