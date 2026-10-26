#ifndef RUNNER_DISTRACTION_PROTECTION_H_
#define RUNNER_DISTRACTION_PROTECTION_H_
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#ifdef GDK_WINDOWING_X11
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <gdk/gdkx.h>
#endif
#include <algorithm>
#include <set>
#include <string>
#include <unistd.h>
#include <vector>

namespace distractions {
struct Host {
  FlMethodChannel *channel = nullptr;
  GtkWindow *main = nullptr;
  GtkWidget *shield = nullptr;
  GtkWidget *label = nullptr;
  GtkWidget *task_label = nullptr;
  guint timer = 0;
  bool discovery = false;
  bool countdown = true;
  GdkPixbuf *mascot = nullptr;
  GtkWidget *mascot_view = nullptr;
  bool quit_allowed = false;
  bool Protected() const {
    return !quit_allowed && expires > g_get_real_time();
  }
  gint64 expires = 0, updated = 0;
  int seconds = 0;
  std::set<std::string> blocked;
  std::string last, attempted, task;
#ifdef GDK_WINDOWING_X11
  GdkDisplay *gdk = nullptr;
  Display *display = nullptr;
  Window root = 0;
  std::vector<std::pair<Window, std::string>> minimized;
  unsigned long Property(Window window, const char *name) {
    Atom type;
    int format = 0;
    unsigned long count = 0, remaining = 0;
    unsigned char *bytes = nullptr;
    unsigned long result = 0;
    if (XGetWindowProperty(display, window, XInternAtom(display, name, False),
                           0, 1, False, AnyPropertyType, &type, &format, &count,
                           &remaining, &bytes) == Success &&
        bytes && count && format == 32)
      result = *reinterpret_cast<unsigned long *>(bytes);
    if (bytes)
      XFree(bytes);
    return result;
  }
  std::pair<std::string, std::string> Identity(Window window) {
    if (!window ||
        Property(window, "_NET_WM_PID") == static_cast<unsigned long>(getpid()))
      return {};
    Atom kind = static_cast<Atom>(Property(window, "_NET_WM_WINDOW_TYPE"));
    if (kind != None &&
        kind != XInternAtom(display, "_NET_WM_WINDOW_TYPE_NORMAL", False))
      return {};
    XClassHint hint{};
    if (!XGetClassHint(display, window, &hint))
      return {};
    std::string value = hint.res_class ? hint.res_class : "";
    if (hint.res_name)
      XFree(hint.res_name);
    if (hint.res_class)
      XFree(hint.res_class);
    if (value.empty() || value.size() > 480 ||
        value.find_first_of("/\\\r\n") != std::string::npos)
      return {};
    std::string lower = value;
    std::transform(
        lower.begin(), lower.end(), lower.begin(),
        [](unsigned char c) { return static_cast<char>(g_ascii_tolower(c)); });
    if (lower == "gnome-shell" || lower == "plasmashell" ||
        lower == "ksmserver" ||
        lower == "polkit-gnome-authentication-agent-1" ||
        lower == "xfce4-panel")
      return {};
    return {"linux:" + value, value};
  }
#endif
  bool Supported() const {
#ifdef GDK_WINDOWING_X11
    return display != nullptr &&
           g_strcmp0(g_getenv("XDG_SESSION_TYPE"), "wayland") != 0 &&
           (!g_getenv("WAYLAND_DISPLAY") || !*g_getenv("WAYLAND_DISPLAY"));
#else
    return false;
#endif
  }
  ~Host() {
    g_signal_handlers_disconnect_by_data(main, this);
    Clear();
    if (mascot)
      g_object_unref(mascot);
    if (timer)
      g_source_remove(timer);
    if (shield)
      gtk_widget_destroy(shield);
    if (channel)
      g_object_unref(channel);
    g_object_unref(main);
  }
  void Emit(const char *event, const std::pair<std::string, std::string> &app) {
    g_autoptr(FlValue) payload = fl_value_new_map();
    fl_value_set_string_take(payload, "id",
                             fl_value_new_string(app.first.c_str()));
    fl_value_set_string_take(payload, "name",
                             fl_value_new_string(app.second.c_str()));
    fl_value_set_string_take(payload, "platform", fl_value_new_string("linux"));
    fl_method_channel_invoke_method(channel, event, payload, nullptr, nullptr,
                                    nullptr);
  }
  void Clear() {
    expires = 0;
    blocked.clear();
    attempted.clear();
    if (shield)
      gtk_widget_hide(shield);
#ifdef GDK_WINDOWING_X11
    if (display) {
      gdk_x11_display_error_trap_push(gdk);
      for (auto &item : minimized)
        if (Identity(item.first).first == item.second &&
            Property(item.first, "WM_STATE") == IconicState)
          XMapWindow(display, item.first);
      XSync(display, False);
      gdk_x11_display_error_trap_pop_ignored(gdk);
      minimized.clear();
    }
#endif
  }
  static void Return(GtkButton *, gpointer data) {
    auto *self = static_cast<Host *>(data);
    gtk_widget_hide(self->shield);
    gtk_window_present(self->main);
  }
  static gboolean Keep(GtkWidget *, GdkEvent *, gpointer) { return TRUE; }
  void Show() {
    if (!shield) {
      shield = gtk_window_new(GTK_WINDOW_TOPLEVEL);
      gtk_window_set_title(GTK_WINDOW(shield), "Focus protection");
      gtk_window_set_decorated(GTK_WINDOW(shield), FALSE);
      gtk_window_set_keep_above(GTK_WINDOW(shield), TRUE);
      gtk_window_stick(GTK_WINDOW(shield));
      g_signal_connect(shield, "delete-event", G_CALLBACK(Keep), nullptr);
      GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 20);
      gtk_widget_set_halign(box, GTK_ALIGN_CENTER);
      gtk_widget_set_valign(box, GTK_ALIGN_CENTER);
      gtk_container_set_border_width(GTK_CONTAINER(box), 32);
      gtk_container_add(GTK_CONTAINER(shield), box);
      mascot_view = gtk_image_new();
      gtk_widget_set_size_request(mascot_view, 180, 180);
      gtk_box_pack_start(GTK_BOX(box), mascot_view, FALSE, FALSE, 0);
      task_label = gtk_label_new("");
      gtk_label_set_line_wrap(GTK_LABEL(task_label), TRUE);
      gtk_label_set_max_width_chars(GTK_LABEL(task_label), 70);
      gtk_box_pack_start(GTK_BOX(box), task_label, FALSE, FALSE, 0);
      label = gtk_label_new("");
      gtk_box_pack_start(GTK_BOX(box), label, FALSE, FALSE, 0);
      GtkWidget *button = gtk_button_new_with_label("Return to task");
      gtk_widget_set_size_request(button, 180, 48);
      g_signal_connect(button, "clicked", G_CALLBACK(Return), this);
      gtk_box_pack_start(GTK_BOX(box), button, FALSE, FALSE, 0);
    }
    gtk_image_set_from_pixbuf(GTK_IMAGE(mascot_view), mascot);
    gtk_label_set_text(GTK_LABEL(task_label), task.c_str());
    int remaining = std::max(
        0,
        seconds - (countdown ? static_cast<int>((g_get_real_time() - updated) /
                                                G_USEC_PER_SEC)
                             : 0));
    gchar *text = g_strdup_printf("%d:%02d", remaining / 60, remaining % 60);
    gtk_label_set_text(GTK_LABEL(label), text);
    g_free(text);
    gtk_widget_show_all(shield);
    gtk_window_fullscreen(GTK_WINDOW(shield));
    gtk_window_present(GTK_WINDOW(shield));
  }
  void Inspect() {
    if (expires && g_get_real_time() >= expires)
      Clear();
#ifdef GDK_WINDOWING_X11
    if (!Supported() || (!discovery && !expires))
      return;
    gdk_x11_display_error_trap_push(gdk);
    Window window = static_cast<Window>(Property(root, "_NET_ACTIVE_WINDOW"));
    if (shield && gtk_widget_get_realized(shield) &&
        window == GDK_WINDOW_XID(gtk_widget_get_window(shield))) {
      Show();
      XSync(display, False);
      gdk_x11_display_error_trap_pop_ignored(gdk);
      return;
    }
    auto app = Identity(window);
    if (discovery && !app.first.empty() && last != app.first) {
      last = app.first;
      Emit("foregroundApp", app);
    }
    if (expires && blocked.count(app.first)) {
      if (attempted != app.first) {
        attempted = app.first;
        Emit("blockedAttempt", app);
      }
      if (Property(window, "WM_STATE") != IconicState &&
          XIconifyWindow(display, window, DefaultScreen(display)))
        minimized.emplace_back(window, app.first);
      Show();
    } else {
      attempted.clear();
      if (shield)
        gtk_widget_hide(shield);
    }
    XSync(display, False);
    gdk_x11_display_error_trap_pop_ignored(gdk);
#endif
  }
  static gboolean CloseMain(GtkWidget *window, GdkEvent *, gpointer data) {
    auto *self = static_cast<Host *>(data);
    if (!self->Protected())
      return FALSE;
    gtk_window_iconify(GTK_WINDOW(window));
    return TRUE;
  }
  static gboolean Tick(gpointer data) {
    static_cast<Host *>(data)->Inspect();
    return G_SOURCE_CONTINUE;
  }
  static void Method(FlMethodChannel *, FlMethodCall *call, gpointer data) {
    auto *self = static_cast<Host *>(data);
    const char *method = fl_method_call_get_name(call);
    g_autoptr(FlMethodResponse) response = nullptr;
    if (g_strcmp0(method, "capabilities") == 0) {
      g_autoptr(FlValue) value = fl_value_new_map();
      bool supported = self->Supported();
      fl_value_set_string_take(value, "supported",
                               fl_value_new_bool(supported));
      fl_value_set_string_take(value, "discoveryAvailable",
                               fl_value_new_bool(supported));
      fl_value_set_string_take(value, "platform", fl_value_new_string("linux"));
      fl_value_set_string_take(
          value, "adapter",
          fl_value_new_string(supported ? "x11-ewmh" : "unavailable"));
      if (!supported)
        fl_value_set_string_take(
            value, "reason",
            fl_value_new_string(
                "This Wayland compositor requires its dedicated adapter; "
                "generic Wayland does not expose foreground applications."));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
    } else if (g_strcmp0(method, "hideShield") == 0) {
      if (self->shield)
        gtk_widget_hide(self->shield);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "allowQuit") == 0) {
      self->quit_allowed = true;
      self->Clear();
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
      g_application_quit(G_APPLICATION(gtk_window_get_application(self->main)));
    } else if (g_strcmp0(method, "startDiscovery") == 0 ||
               g_strcmp0(method, "stopDiscovery") == 0) {
      self->discovery = g_strcmp0(method, "startDiscovery") == 0;
      self->last.clear();
      self->Inspect();
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "clearProtection") == 0) {
      self->Clear();
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "setProtection") == 0 ||
               g_strcmp0(method, "configureProtection") == 0 ||
               g_strcmp0(method, "setShield") == 0) {
      FlValue *args = fl_method_call_get_args(call);
      FlValue *active = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                            ? fl_value_lookup_string(args, "active")
                            : nullptr;
      bool valid = active && fl_value_get_type(active) == FL_VALUE_TYPE_BOOL;
      if (valid && !fl_value_get_bool(active)) {
        self->Clear();
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
      } else if (valid && !self->Supported() &&
                 g_strcmp0(method, "setProtection") == 0)
        response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            "unsupported",
            "Foreground protection is unavailable on this compositor.",
            nullptr));
      else {
        FlValue *ids =
            valid ? fl_value_lookup_string(args, "blockedApps") : nullptr;
        FlValue *title =
            valid ? fl_value_lookup_string(args, "taskTitle") : nullptr;
        FlValue *expiry =
            valid ? fl_value_lookup_string(args, "expiresAt") : nullptr;
        FlValue *remaining =
            valid ? fl_value_lookup_string(args, "remainingSeconds") : nullptr;
        valid = ids && fl_value_get_type(ids) == FL_VALUE_TYPE_LIST &&
                fl_value_get_length(ids) <= 4096 && title &&
                fl_value_get_type(title) == FL_VALUE_TYPE_STRING && expiry &&
                fl_value_get_type(expiry) == FL_VALUE_TYPE_STRING &&
                remaining &&
                fl_value_get_type(remaining) == FL_VALUE_TYPE_INT &&
                fl_value_get_int(remaining) >= 0 &&
                fl_value_get_int(remaining) <= G_MAXINT;
        std::set<std::string> next;
        if (valid)
          for (size_t i = 0; i < fl_value_get_length(ids); i++) {
            FlValue *item = fl_value_get_list_value(ids, i);
            if (fl_value_get_type(item) != FL_VALUE_TYPE_STRING) {
              valid = false;
              break;
            }
            std::string id = fl_value_get_string(item);
            if (id.size() > 512 ||
                id.find_first_of("/\\") != std::string::npos) {
              valid = false;
              break;
            }
            next.insert(id);
          }
        GDateTime *date = valid ? g_date_time_new_from_iso8601(
                                      fl_value_get_string(expiry), nullptr)
                                : nullptr;
        if (!valid || !date)
          response = FL_METHOD_RESPONSE(fl_method_error_response_new(
              "invalid_protection", "Invalid protection snapshot.", nullptr));
        else {
          self->expires = g_date_time_to_unix(date) * G_USEC_PER_SEC;
          g_date_time_unref(date);
          FlValue *image = fl_value_lookup_string(args, "mascotImage");
          if (image && fl_value_get_type(image) == FL_VALUE_TYPE_UINT8_LIST &&
              fl_value_get_length(image) <= 8 * 1024 * 1024) {
            GdkPixbufLoader *loader = gdk_pixbuf_loader_new();
            GError *error = nullptr;
            if (gdk_pixbuf_loader_write(loader, fl_value_get_uint8_list(image),
                                        fl_value_get_length(image), &error) &&
                gdk_pixbuf_loader_close(loader, &error)) {
              GdkPixbuf *original = gdk_pixbuf_loader_get_pixbuf(loader);
              if (original) {
                GdkPixbuf *scaled = gdk_pixbuf_scale_simple(
                    original, 180, 180, GDK_INTERP_BILINEAR);
                g_set_object(&self->mascot, scaled);
                if (scaled)
                  g_object_unref(scaled);
              }
            }
            if (error)
              g_error_free(error);
            g_object_unref(loader);
          }
          FlValue *countdown = fl_value_lookup_string(args, "countdown");
          self->countdown =
              !countdown ||
              fl_value_get_type(countdown) != FL_VALUE_TYPE_BOOL ||
              fl_value_get_bool(countdown);
          self->blocked = std::move(next);
          self->task = fl_value_get_string(title);
          self->seconds = static_cast<int>(fl_value_get_int(remaining));
          self->updated = g_get_real_time();
          self->Inspect();
          if (g_strcmp0(method, "setShield") == 0 &&
              self->expires > g_get_real_time())
            self->Show();
          response =
              FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
        }
      }
    } else
      response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(call, response, nullptr);
  }
  Host(FlView *view, GtkWindow *window) : main(window) {
    g_object_ref(main);
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    channel = fl_method_channel_new(
        fl_engine_get_binary_messenger(fl_view_get_engine(view)),
        "pomodoist/distractions", FL_METHOD_CODEC(codec));
#ifdef GDK_WINDOWING_X11
    gdk = gtk_widget_get_display(GTK_WIDGET(view));
    if (GDK_IS_X11_DISPLAY(gdk)) {
      display = gdk_x11_display_get_xdisplay(gdk);
      root = DefaultRootWindow(display);
    }
#endif
    g_signal_connect(main, "delete-event", G_CALLBACK(CloseMain), this);
    fl_method_channel_set_method_call_handler(channel, Method, this, nullptr);
    timer = g_timeout_add(500, Tick, this);
  }
};
} // namespace distractions
#endif
