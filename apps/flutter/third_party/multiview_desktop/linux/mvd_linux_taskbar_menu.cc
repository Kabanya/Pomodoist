#include "mvd_linux_taskbar_menu.h"

#include "mvd_linux_log.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#include <gtk/gtk.h>

#include <string>
#include <utility>
#include <vector>

#define MVD_LOG MVD_LOG_PLUGIN

namespace {

FlMethodChannel* g_event_channel = nullptr;
std::vector<std::string> g_taskbar_action_names;
std::vector<std::string> g_desktop_action_ids;

void emit_taskbar_menu_item_selected(int id) {
  if (!g_event_channel) {
    return;
  }
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "eventName",
                           fl_value_new_string("taskbarMenuItemSelected"));
  fl_value_set_string_take(map, "id", fl_value_new_int(id));
  fl_method_channel_invoke_method(g_event_channel, "onEvent", map, nullptr,
                                  nullptr, nullptr);
}

void on_taskbar_menu_action_activated(GSimpleAction* /*action*/,
                                      GVariant* /*parameter*/,
                                      gpointer user_data) {
  emit_taskbar_menu_item_selected(GPOINTER_TO_INT(user_data));
}

bool int_from_fl_value(FlValue* value, int* out) {
  if (!value || !out || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return false;
  }
  *out = static_cast<int>(fl_value_get_int(value));
  return true;
}

void clear_taskbar_menu_actions(GtkApplication* app) {
  for (const auto& name : g_taskbar_action_names) {
    g_action_map_remove_action(G_ACTION_MAP(app), name.c_str());
  }
  g_taskbar_action_names.clear();
  gtk_application_set_app_menu(app, nullptr);
}

void remove_desktop_action_groups(GKeyFile* key_file) {
  for (const auto& action_id : g_desktop_action_ids) {
    g_autofree gchar* group =
        g_strdup_printf("Desktop Action %s", action_id.c_str());
    g_key_file_remove_group(key_file, group, nullptr);
  }
  g_desktop_action_ids.clear();
}

void sync_taskbar_desktop_file(
    const std::vector<std::pair<int, std::string>>& entries) {
  GApplication* application = g_application_get_default();
  if (!application) {
    return;
  }
  const char* app_id = g_application_get_application_id(application);
  if (!app_id || app_id[0] == '\0') {
    MVD_LOG("sync_taskbar_desktop_file  SKIP: no application-id");
    return;
  }

  g_autofree gchar* desktop_dir =
      g_build_filename(g_get_user_data_dir(), "applications", nullptr);
  g_mkdir_with_parents(desktop_dir, 0755);

  g_autofree gchar* desktop_path =
      g_build_filename(desktop_dir, g_strconcat(app_id, ".desktop", nullptr),
                       nullptr);

  g_autoptr(GKeyFile) key_file = g_key_file_new();
  GError* error = nullptr;
  if (!g_key_file_load_from_file(key_file, desktop_path, G_KEY_FILE_NONE,
                                 &error)) {
    g_clear_error(&error);
  }

  remove_desktop_action_groups(key_file);

  g_key_file_set_string(key_file, "Desktop Entry", "Type", "Application");
  g_key_file_set_string(key_file, "Desktop Entry", "Version", "1.0");
  g_key_file_set_string(key_file, "Desktop Entry", "Terminal", "false");
  g_key_file_set_string(key_file, "Desktop Entry", "DBusActivatable", "true");

  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe) {
    g_key_file_set_string(key_file, "Desktop Entry", "Exec", exe);
  }

  const char* prgname = g_get_prgname();
  if (prgname && prgname[0] != '\0') {
    g_key_file_set_string(key_file, "Desktop Entry", "StartupWMClass", prgname);
    if (!g_key_file_has_key(key_file, "Desktop Entry", "Name", nullptr)) {
      g_key_file_set_string(key_file, "Desktop Entry", "Name", prgname);
    }
  } else if (!g_key_file_has_key(key_file, "Desktop Entry", "Name", nullptr)) {
    g_key_file_set_string(key_file, "Desktop Entry", "Name", app_id);
  }

  if (entries.empty()) {
    g_key_file_remove_key(key_file, "Desktop Entry", "Actions", nullptr);
  } else {
    g_autoptr(GString) actions = g_string_new(nullptr);
    for (const auto& entry : entries) {
      g_autofree gchar* action_id =
          g_strdup_printf("taskbar-%d", entry.first);
      g_desktop_action_ids.emplace_back(action_id);
      if (actions->len > 0) {
        g_string_append_c(actions, ';');
      }
      g_string_append(actions, action_id);

      g_autofree gchar* group =
          g_strdup_printf("Desktop Action %s", action_id);
      g_key_file_set_string(key_file, group, "Name", entry.second.c_str());
      if (exe) {
        g_key_file_set_string(key_file, group, "Exec", exe);
      }
    }
    g_string_append_c(actions, ';');
    g_key_file_set_string(key_file, "Desktop Entry", "Actions", actions->str);
  }

  g_autofree gchar* data =
      g_key_file_to_data(key_file, nullptr, &error);
  if (!data) {
    MVD_LOG("sync_taskbar_desktop_file  failed to serialize: %s",
            error ? error->message : "unknown");
    g_clear_error(&error);
    return;
  }
  if (!g_file_set_contents(desktop_path, data, -1, &error)) {
    MVD_LOG("sync_taskbar_desktop_file  failed to write '%s': %s",
            desktop_path, error ? error->message : "unknown");
    g_clear_error(&error);
    return;
  }

  g_autofree gchar* update_cmd =
      g_strdup_printf("update-desktop-database %s", desktop_dir);
  g_spawn_command_line_async(update_cmd, nullptr);
  MVD_LOG("sync_taskbar_desktop_file  wrote '%s' with %zu action(s)",
          desktop_path, entries.size());
}

void set_taskbar_menu_items(FlValue* items) {
  GApplication* application = g_application_get_default();
  if (!application || !GTK_IS_APPLICATION(application)) {
    MVD_LOG("set_taskbar_menu_items  SKIP: no GtkApplication");
    return;
  }
  GtkApplication* app = GTK_APPLICATION(application);

  if (g_application_get_flags(application) & G_APPLICATION_NON_UNIQUE) {
    MVD_LOG("set_taskbar_menu_items  WARN: G_APPLICATION_NON_UNIQUE prevents"
            " DBusActivatable taskbar menus; use default GApplication flags");
  }

  clear_taskbar_menu_actions(app);

  std::vector<std::pair<int, std::string>> desktop_entries;

  if (items && fl_value_get_type(items) == FL_VALUE_TYPE_LIST) {
    const size_t count = fl_value_get_length(items);
    g_autoptr(GMenu) menu = g_menu_new();
    g_autoptr(GMenu) section = g_menu_new();

    for (size_t i = 0; i < count; ++i) {
      FlValue* item = fl_value_get_list_value(items, i);
      if (!item || fl_value_get_type(item) != FL_VALUE_TYPE_MAP) {
        continue;
      }
      int id = 0;
      if (!int_from_fl_value(fl_value_lookup_string(item, "id"), &id)) {
        continue;
      }
      FlValue* title_val = fl_value_lookup_string(item, "title");
      if (!title_val || fl_value_get_type(title_val) != FL_VALUE_TYPE_STRING) {
        continue;
      }
      const char* title = fl_value_get_string(title_val);
      if (!title || title[0] == '\0') {
        continue;
      }

      g_autofree gchar* action_name = g_strdup_printf("taskbar-%d", id);
      g_taskbar_action_names.emplace_back(action_name);

      g_autoptr(GSimpleAction) action =
          g_simple_action_new(action_name, nullptr);
      g_signal_connect(action, "activate",
                       G_CALLBACK(on_taskbar_menu_action_activated),
                       GINT_TO_POINTER(id));
      g_action_map_add_action(G_ACTION_MAP(app), G_ACTION(action));

      g_autofree gchar* detailed = g_strdup_printf("app.%s", action_name);
      g_menu_append(section, title, detailed);
      desktop_entries.emplace_back(id, title);
    }

    if (!g_taskbar_action_names.empty()) {
      g_menu_append_section(menu, nullptr, G_MENU_MODEL(section));
      gtk_application_set_app_menu(app, G_MENU_MODEL(menu));
    }
  }

  sync_taskbar_desktop_file(desktop_entries);
  MVD_LOG("set_taskbar_menu_items  installed %zu action(s)",
          g_taskbar_action_names.size());
}

}  // namespace

void mvd_linux_taskbar_menu_set_channel(FlMethodChannel* channel) {
  g_event_channel = channel;
}

gboolean mvd_linux_set_taskbar_menu_on_main_thread(gpointer data) {
  g_autoptr(FlValue) items = static_cast<FlValue*>(data);
  set_taskbar_menu_items(items);
  return G_SOURCE_REMOVE;
}

void mvd_linux_set_taskbar_menu(FlValue* items) {
  if (items) {
    fl_value_ref(items);
  }
  g_main_context_invoke(nullptr, mvd_linux_set_taskbar_menu_on_main_thread,
                      items);
}
