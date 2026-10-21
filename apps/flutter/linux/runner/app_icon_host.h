#ifndef RUNNER_APP_ICON_HOST_H_
#define RUNNER_APP_ICON_HOST_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <string>

struct AppIconHost {
  GtkApplication *application;
  FlMethodChannel *channel = nullptr;
  GdkPixbuf *image = nullptr;
  std::string selected = "icon-light-pomo";
  ~AppIconHost() {
    g_clear_object(&channel);
    g_clear_object(&image);
  }
};

static std::string app_icon_flavor() {
  const std::string id = APPLICATION_ID;
  if (id == "com.finchforge.pomodoist.dev")
    return "development";
  if (id == "com.finchforge.pomodoist.stg")
    return "staging";
  return "production";
}

static std::string app_icon_exec(const char *executable) {
  std::string quoted = "\"";
  for (const char *c = executable; *c; ++c) {
    if (*c == '%')
      quoted += '%';
    if (*c == '\\' || *c == '"' || *c == '$' || *c == '`')
      quoted += '\\';
    quoted += *c;
  }
  return quoted + "\" %u";
}

static gboolean app_icon_launcher(const char *executable, const char *source,
                                  const char *icon, GError **error) {
  g_autofree gchar *desktop_name =
      g_strconcat(APPLICATION_ID, ".desktop", nullptr);
  g_autofree gchar *applications =
      g_build_filename(g_get_user_data_dir(), "applications", nullptr);
  g_autofree gchar *destination =
      g_build_filename(applications, desktop_name, nullptr);
  g_autoptr(GKeyFile) entry = g_key_file_new();
  gboolean loaded = FALSE;
  if (g_file_test(destination, G_FILE_TEST_EXISTS)) {
    // Existing personal launchers without our marker belong to the user.
    if (g_file_test(destination, G_FILE_TEST_IS_SYMLINK))
      return TRUE;
    if (!g_key_file_load_from_file(entry, destination, G_KEY_FILE_KEEP_COMMENTS,
                                   error))
      return FALSE;
    loaded = TRUE;
  } else {
    for (const gchar *const *directory = g_get_system_data_dirs(); *directory;
         ++directory) {
      g_autofree gchar *path =
          g_build_filename(*directory, "applications", desktop_name, nullptr);
      if (!g_file_test(path, G_FILE_TEST_EXISTS))
        continue;
      if (!g_key_file_load_from_file(entry, path, G_KEY_FILE_KEEP_COMMENTS,
                                     error))
        return FALSE;
      loaded = TRUE;
      break;
    }
  }
  if (loaded && !g_key_file_get_boolean(entry, "Desktop Entry",
                                        "X-Pomodoist-Managed", nullptr))
    return TRUE;
  if (!loaded) {
    // A default icon must not create launcher entries for development runs.
    if (g_strcmp0(icon, "icon-light-pomo") == 0)
      return TRUE;
    const char *appimage = g_getenv("APPIMAGE");
    const char *launch =
        appimage && g_path_is_absolute(appimage) ? appimage : executable;
    const std::string command = app_icon_exec(launch);
    g_key_file_set_string(entry, "Desktop Entry", "Type", "Application");
    g_key_file_set_string(entry, "Desktop Entry", "Name", APP_DISPLAY_NAME);
    g_key_file_set_string(entry, "Desktop Entry", "Exec", command.c_str());
    g_key_file_set_string(entry, "Desktop Entry", "StartupWMClass",
                          APPLICATION_ID);
    g_key_file_set_string(entry, "Desktop Entry", "Categories",
                          "Office;ProjectManagement;");
    const std::string flavor = app_icon_flavor();
    const std::string scheme = flavor == "production"    ? "pomodoist"
                               : flavor == "development" ? "pomodoist-dev"
                                                         : "pomodoist-stg";
    g_key_file_set_string(entry, "Desktop Entry", "MimeType",
                          ("x-scheme-handler/" + scheme + ";").c_str());
    g_key_file_set_boolean(entry, "Desktop Entry", "Terminal", FALSE);
    g_key_file_set_boolean(entry, "Desktop Entry", "X-Pomodoist-Managed", TRUE);
  }
  g_autofree gchar *icons =
      g_build_filename(g_get_user_data_dir(), APPLICATION_ID, "icons", nullptr);
  if (g_mkdir_with_parents(icons, 0700) != 0 ||
      g_mkdir_with_parents(applications, 0700) != 0) {
    g_set_error_literal(error, G_FILE_ERROR, G_FILE_ERROR_ACCES,
                        "Could not create app icon directories.");
    return FALSE;
  }
  g_autofree gchar *image_name = g_strconcat(icon, ".png", nullptr);
  g_autofree gchar *image_path = g_build_filename(icons, image_name, nullptr);
  g_autofree gchar *bytes = nullptr;
  gsize length = 0;
  if (!g_file_get_contents(source, &bytes, &length, error) ||
      !g_file_set_contents(image_path, bytes, length, error))
    return FALSE;
  // Keep the selected icon outside an AppImage's temporary mount.
  g_key_file_set_string(entry, "Desktop Entry", "Icon", image_path);
  g_autofree gchar *contents = g_key_file_to_data(entry, &length, error);
  return contents && g_file_set_contents(destination, contents, length, error);
}

static void app_icon_window_added(GtkApplication *, GtkWindow *window,
                                  gpointer data) {
  auto *host = static_cast<AppIconHost *>(data);
  if (host->image)
    gtk_window_set_icon(window, host->image);
}

static void app_icon_method_call(FlMethodChannel *, FlMethodCall *call,
                                 gpointer data) {
  auto *host = static_cast<AppIconHost *>(data);
  const gchar *method = fl_method_call_get_name(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "getIcon") == 0) {
    g_autoptr(FlValue) value = fl_value_new_string(host->selected.c_str());
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (g_strcmp0(method, "setIcon") == 0) {
    FlValue *args = fl_method_call_get_args(call);
    FlValue *value = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                         ? fl_value_lookup_string(args, "icon")
                         : nullptr;
    const char *icon = value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
                           ? fl_value_get_string(value)
                           : "";
    if (g_strcmp0(icon, "classic") != 0 &&
        g_strcmp0(icon, "icon-light-pomo") != 0) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "invalid_icon", "Unsupported app icon.", nullptr));
    } else {
      g_autoptr(GError) error = nullptr;
      g_autofree gchar *executable = g_file_read_link("/proc/self/exe", &error);
      g_autoptr(GdkPixbuf) image = nullptr;
      if (executable) {
        g_autofree gchar *directory = g_path_get_dirname(executable);
        const std::string asset = app_icon_flavor() + "/" + icon + ".png";
        g_autofree gchar *path = g_build_filename(
            directory, "data", "flutter_assets", "assets", "branding",
            "app_icons", "generated", asset.c_str(), nullptr);
        image = gdk_pixbuf_new_from_file(path, &error);
        if (image && app_icon_launcher(executable, path, icon, &error)) {
          g_set_object(&host->image, image);
          gtk_window_set_default_icon(image);
          for (GList *window = gtk_application_get_windows(host->application);
               window; window = window->next)
            gtk_window_set_icon(GTK_WINDOW(window->data), image);
          host->selected = icon;
          response =
              FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
        }
      }
      if (!response)
        response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            "icon_failed", error ? error->message : "Could not apply app icon.",
            nullptr));
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

static void configure_app_icon_channel(GtkApplication *application,
                                       FlView *view) {
  auto *host = new AppIconHost();
  host->application = application;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  host->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "pomodoist/app_icon", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(host->channel, app_icon_method_call,
                                            host, nullptr);
  g_signal_connect(application, "window-added",
                   G_CALLBACK(app_icon_window_added), host);
  g_object_set_data_full(
      G_OBJECT(application), "pomodoist-app-icon", host,
      [](gpointer data) { delete static_cast<AppIconHost *>(data); });
}

#endif
