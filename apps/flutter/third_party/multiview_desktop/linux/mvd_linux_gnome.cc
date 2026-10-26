#include "mvd_linux_gnome.h"
#include "mvd_linux_gnome_policy.h"
#include <gio/gio.h>
#include <map>
#include <cmath>
#include <memory>
#include <string>
#include <utility>

namespace {
constexpr char kName[] = "com.pomodoist.Pomo.Gnome1";
constexpr char kPath[] = "/com/pomodoist/Pomo/Gnome1";
constexpr char kShellName[] = "org.gnome.Shell";
constexpr char kShellPath[] = "/org/gnome/Shell";
constexpr char kExtensions[] = "org.gnome.Shell.Extensions";
constexpr char kUuid[] = "pomo@pomodoist.com";
using Result = std::function<void(FlValue*, const char*)>;
struct Window {
  GtkWindow* widget;
  std::string role;
  FlValue* bounds = nullptr;
  FlValue* desired = fl_value_new_map();
  bool intent = false;
  bool registered = false;
  bool placing = false;
  bool placed = false;
  unsigned desired_revision = 0;
  unsigned session_revision = 0;
  ~Window() { if (bounds) fl_value_unref(bounds); fl_value_unref(desired); }
};
std::map<std::string, std::unique_ptr<Window>> windows;
GDBusConnection* bus = nullptr;
guint watcher = 0, subscription = 0;
unsigned generation = 0, following_request = 0;
std::string owner, error_text, extension_state = "notInstalled", shell_version;
FlValue* capabilities = nullptr;
FlValue* shell_cursor = nullptr;
bool following = false, installed = false, needs_relogin = false, global_disabled = false;
int loaded_version = 0, installed_version = 0, protocol_version = 0, shell_extension_state = 0;
const char* Text(FlValue* map, const char* key) {
  FlValue* value = map && fl_value_get_type(map) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(map, key) : nullptr;
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING ? fl_value_get_string(value) : "";
}
FlValue* Field(FlValue* map, const char* key) {
  return map && fl_value_get_type(map) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(map, key) : nullptr;
}
bool Flag(FlValue* map, const char* key) {
  FlValue* value = Field(map, key);
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(value);
}
int Integer(FlValue* map, const char* key) {
  FlValue* value = Field(map, key);
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_INT ? fl_value_get_int(value) : 0;
}
void String(FlValue* map, const char* key, const char* value) {
  fl_value_set_string_take(map, key, fl_value_new_string(value));
}
void Replace(FlValue*& target, FlValue* value) {
  FlValue* retained = value ? fl_value_ref(value) : nullptr;
  if (target) fl_value_unref(target);
  target = retained;
}
std::string Token(GtkWindow* window) {
  const auto* token = static_cast<const char*>(g_object_get_data(G_OBJECT(window), "mvd-gnome-token"));
  return token ? token : "";
}
bool Active() {
  return !owner.empty() && capabilities && extension_state == "active" && Flag(capabilities, "supported") && !global_disabled;
}
bool Suppressed() { return Flag(capabilities, "suppressed"); }
void UpdateState() {
  extension_state = mvd::ExtensionState(!owner.empty() && capabilities, protocol_version,
      loaded_version, installed, needs_relogin, global_disabled);
  if ((!shell_version.empty() && !mvd::SupportedGnomeShell(shell_version)) ||
      shell_extension_state == 4 ||
      (!owner.empty() && protocol_version && protocol_version != 1) ||
      (installed && installed_version && installed_version != 1 && !needs_relogin && !capabilities))
    extension_state = "incompatible";
  else if (shell_extension_state == 3) extension_state = "error";
}
void Call(const char* method, GVariant* args, Result done) {
  if (!bus || owner.empty()) { if (done) done(nullptr, "GNOME bridge unavailable"); return; }
  struct Pending { unsigned epoch; Result callback; };
  auto* pending = new Pending{generation, std::move(done)};
  g_dbus_connection_call(bus, owner.c_str(), kPath, kName, method, args,
      G_VARIANT_TYPE("(s)"), G_DBUS_CALL_FLAGS_NONE, 5000, nullptr,
      [](GObject* object, GAsyncResult* result, gpointer data) {
        std::unique_ptr<Pending> p(static_cast<Pending*>(data));
        g_autoptr(GError) error = nullptr;
        g_autoptr(GVariant) reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(object), result, &error);
        if (p->epoch != generation) { if (p->callback) p->callback(nullptr, "GNOME bridge connection changed"); return; }
        g_autoptr(FlValue) value = nullptr;
        if (reply) {
          const char* json = nullptr; g_variant_get(reply, "(&s)", &json);
          g_autoptr(FlJsonMessageCodec) codec = fl_json_message_codec_new();
          value = fl_json_message_codec_decode(codec, json, &error);
        }
        if (p->callback) p->callback(value, error ? error->message : nullptr);
      }, pending);
}
void MergeGeometry(FlValue* target, FlValue* source) {
  for (const char* key : {"x", "y", "width", "height", "displayId"})
    if (FlValue* value = Field(source, key)) fl_value_set_string(target, key, value);
}
void Command(const std::string& token, const char* method, FlValue* payload, Result done) {
  g_autoptr(FlJsonMessageCodec) codec = fl_json_message_codec_new();
  g_autoptr(FlValue) empty = fl_value_new_map();
  g_autoptr(FlValue) geometry = fl_value_new_map();
  if (g_str_equal(method, "configure")) { MergeGeometry(geometry, payload); payload = geometry; }
  g_autofree char* json = fl_json_message_codec_encode(codec, payload ? payload : empty, nullptr);
  Call("Command", g_variant_new("(sss)", token.c_str(), method, json ? json : "{}"), std::move(done));
}
void Reconcile(const std::string& token);
void ReadSettings();
void SetBounds(Window& w, FlValue* value) {
  const bool valid = value && fl_value_get_type(value) == FL_VALUE_TYPE_MAP;
  if (w.bounds && !valid) {
    ++w.session_revision; w.placed = w.placing = false;
  }
  Replace(w.bounds, valid ? value : nullptr);
  using Refresh = void (*)(GtkWindow*);
  auto refresh = reinterpret_cast<Refresh>(g_object_get_data(G_OBJECT(w.widget), "mvd-pomo-input-refresh"));
  if (refresh) refresh(w.widget);
}
void Reconcile(const std::string& token) {
  auto it = windows.find(token); if (it == windows.end()) return;
  Window& w = *it->second;
  const auto action = mvd::GnomePlacement(Active(), Suppressed(), w.intent,
      w.registered, w.bounds != nullptr, w.placed, w.placing);
  if (action == mvd::GnomePlacementAction::hide) {
    w.placing = false; w.placed = false; SetBounds(w, nullptr);
    gtk_widget_hide(GTK_WIDGET(w.widget)); return;
  }
  if (action == mvd::GnomePlacementAction::wait) return;
  if (!gtk_widget_get_visible(GTK_WIDGET(w.widget))) {
    SetBounds(w, nullptr); w.placed = w.placing = false;
    gtk_widget_set_opacity(GTK_WIDGET(w.widget), 0);
    gtk_widget_show(GTK_WIDGET(w.widget));
    return;
  }
  if (action == mvd::GnomePlacementAction::map) {
    // A mapped, fully transparent actor lets Shell resolve its role without a
    // flash at GTK's guessed coordinates. Shell reveals only placed geometry.
    gtk_widget_set_opacity(GTK_WIDGET(w.widget), 0);
    gtk_widget_show(GTK_WIDGET(w.widget)); return;
  }
  if (action == mvd::GnomePlacementAction::place) {
    w.placing = true;
    const unsigned revision = w.desired_revision;
    const unsigned session = w.session_revision;
    Command(token, "configure", w.desired, [token, revision, session](FlValue* result, const char* error) {
      auto found = windows.find(token); if (found == windows.end()) return;
      auto& window = *found->second;
      if (window.session_revision != session) return;
      window.placing = false;
      if (error || !result || fl_value_get_type(result) != FL_VALUE_TYPE_MAP) {
        gtk_widget_hide(GTK_WIDGET(window.widget)); return;
      }
      SetBounds(window, result); window.placed = revision == window.desired_revision;
      Reconcile(token);
    });
  } else if (action == mvd::GnomePlacementAction::reveal) {
    gtk_widget_set_opacity(GTK_WIDGET(w.widget), 1);
    gtk_widget_show(GTK_WIDGET(w.widget));
  }
}
bool ValidCursor(FlValue* cursor) {
  for (const char* key : {"x", "y"}) {
    FlValue* coordinate = Field(cursor, key);
    if (!coordinate) return false;
    if (fl_value_get_type(coordinate) == FL_VALUE_TYPE_FLOAT) {
      if (!std::isfinite(fl_value_get_float(coordinate))) return false;
    } else if (fl_value_get_type(coordinate) != FL_VALUE_TYPE_INT) return false;
  }
  return true;
}
void ApplyCapabilities(FlValue* value) {
  ReadSettings();
  if (!value || fl_value_get_type(value) != FL_VALUE_TYPE_MAP || Integer(value, "protocolVersion") != 1) {
    error_text = "Incompatible GNOME bridge protocol";
    protocol_version = value ? Integer(value, "protocolVersion") : 0;
    Replace(capabilities, nullptr); Replace(shell_cursor, nullptr); extension_state = "incompatible";
    for (auto& entry : windows) {
      entry.second->placed = entry.second->placing = false;
      SetBounds(*entry.second, nullptr); gtk_widget_hide(GTK_WIDGET(entry.second->widget));
    }
    return;
  }
  FlValue* old_displays = Field(capabilities, "displays");
  FlValue* next_displays = Field(value, "displays");
  if (old_displays && next_displays && !fl_value_equal(old_displays, next_displays)) Replace(shell_cursor, nullptr);
  if (Flag(value, "suppressed")) Replace(shell_cursor, nullptr);
  else if (FlValue* sample = Field(value, "cursor")) Replace(shell_cursor, ValidCursor(sample) ? sample : nullptr);
  Replace(capabilities, value);
  protocol_version = Integer(value, "protocolVersion");
  loaded_version = Integer(value, "extensionVersion");
  if (*Text(value, "shellVersion")) shell_version = Text(value, "shellVersion");
  installed = true;
  if (loaded_version == 1) needs_relogin = false;
  error_text.clear(); UpdateState();
  FlValue* encoded = Field(value, "windows");
  for (auto& entry : windows) {
    auto* bounds = Field(encoded, entry.first.c_str());
    if (bounds || (encoded && fl_value_get_type(encoded) == FL_VALUE_TYPE_MAP)) {
      SetBounds(*entry.second, bounds);
      if (entry.second->bounds) entry.second->registered = true;
      else entry.second->placed = false;
    }
    Reconcile(entry.first);
  }
}
void Register(const std::string& token) {
  auto found = windows.find(token); if (found == windows.end() || !Active()) return;
  const unsigned session = found->second->session_revision;
  mvd_gnome_register_token(token.c_str(), found->second->role.c_str(),
      [token, session](FlValue* value, const char* error) {
        auto it = windows.find(token); if (it == windows.end() || it->second->session_revision != session) return;
        if (!error && value) {
          it->second->registered = true;
          auto* bounds = Field(value, "bounds"); if (bounds) SetBounds(*it->second, bounds);
          Reconcile(token);
        }
      });
}
GSettings* Settings() {
  GSettingsSchemaSource* source = g_settings_schema_source_get_default();
  if (!source) return nullptr;
  g_autoptr(GSettingsSchema) schema = g_settings_schema_source_lookup(source, "org.gnome.shell", TRUE);
  if (!schema) return nullptr;
  return g_settings_new_full(schema, nullptr, nullptr);
}
void ReadSettings() {
  g_autoptr(GSettings) settings = Settings();
  global_disabled = settings && g_settings_get_boolean(settings, "disable-user-extensions");
}
void PreserveEnabled() {
  g_autoptr(GSettings) settings = Settings(); if (!settings) return;
  g_auto(GStrv) values = g_settings_get_strv(settings, "enabled-extensions");
  std::vector<std::string> entries;
  for (size_t i = 0; values && values[i]; ++i) entries.emplace_back(values[i]);
  entries = mvd::EnableUuid(std::move(entries));
  std::vector<const char*> encoded;
  for (const auto& value : entries) encoded.push_back(value.c_str());
  encoded.push_back(nullptr);
  g_settings_set_strv(settings, "enabled-extensions", encoded.data());
}
void ShellInfo(std::function<void()> done) {
  ReadSettings();
  if (!bus) {
    auto* pending = new std::function<void()>(std::move(done));
    g_bus_get(G_BUS_TYPE_SESSION, nullptr, [](GObject*, GAsyncResult* result, gpointer data) {
      std::unique_ptr<std::function<void()>> cb(static_cast<std::function<void()>*>(data));
      g_autoptr(GError) error = nullptr;
      GDBusConnection* connection = g_bus_get_finish(result, &error);
      if (!connection) { error_text = error->message; extension_state = "error"; (*cb)(); return; }
      g_set_object(&bus, connection); g_object_unref(connection); ShellInfo(std::move(*cb));
    }, pending);
    return;
  }
  auto* callback = new std::function<void()>(std::move(done));
  g_dbus_connection_call(bus, kShellName, kShellPath, kExtensions, "GetExtensionInfo",
      g_variant_new("(s)", kUuid), G_VARIANT_TYPE("(a{sv})"), G_DBUS_CALL_FLAGS_NONE, 3000, nullptr,
      [](GObject* object, GAsyncResult* result, gpointer data) {
        std::unique_ptr<std::function<void()>> cb(static_cast<std::function<void()>*>(data));
        g_autoptr(GError) error = nullptr;
        g_autoptr(GVariant) reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(object), result, &error);
        if (reply) {
          g_autoptr(GVariant) info = g_variant_get_child_value(reply, 0);
          installed = g_variant_n_children(info) != 0;
          g_autoptr(GVariant) state = g_variant_lookup_value(info, "state", nullptr);
          g_autoptr(GVariant) version = g_variant_lookup_value(info, "version", nullptr);
          int shell_state = state && g_variant_is_of_type(state, G_VARIANT_TYPE_DOUBLE) ? g_variant_get_double(state) :
              state && g_variant_is_of_type(state, G_VARIANT_TYPE_INT32) ? g_variant_get_int32(state) : 0;
          int disk_version = version && g_variant_is_of_type(version, G_VARIANT_TYPE_DOUBLE) ? g_variant_get_double(version) :
              version && g_variant_is_of_type(version, G_VARIANT_TYPE_INT32) ? g_variant_get_int32(version) : 0;
          shell_extension_state = shell_state;
          if (shell_state == 3) error_text = "GNOME Shell could not load the Pomo extension";
          installed_version = disk_version;
        }
        UpdateState(); (*cb)();
      }, callback);
}
void ShellVersion(std::function<void()> done) {
  if (!bus) { done(); return; }
  auto* callback = new std::function<void()>(std::move(done));
  g_dbus_connection_call(bus, kShellName, kShellPath, "org.freedesktop.DBus.Properties", "Get",
      g_variant_new("(ss)", kShellName, "ShellVersion"), G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE,
      3000, nullptr, [](GObject* object, GAsyncResult* result, gpointer data) {
        std::unique_ptr<std::function<void()>> cb(static_cast<std::function<void()>*>(data));
        g_autoptr(GError) error = nullptr;
        g_autoptr(GVariant) reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(object), result, &error);
        if (reply) {
          g_autoptr(GVariant) boxed = g_variant_get_child_value(reply, 0);
          g_autoptr(GVariant) value = g_variant_get_variant(boxed);
          if (g_variant_is_of_type(value, G_VARIANT_TYPE_STRING)) shell_version = g_variant_get_string(value, nullptr);
        }
        UpdateState();
        if (shell_version.empty()) {
          extension_state = "error";
          error_text = error ? error->message : "GNOME Shell version unavailable";
        }
        for (const auto& entry : windows) Reconcile(entry.first);
        (*cb)();
      }, callback);
}
void Enable(std::function<void()> done) {
  ReadSettings();
  if (global_disabled) { UpdateState(); done(); return; }
  if (!bus) { error_text = "GNOME Shell session bus unavailable"; extension_state = "error"; done(); return; }
  auto* callback = new std::function<void()>(std::move(done));
  g_dbus_connection_call(bus, kShellName, kShellPath, kExtensions, "EnableExtension",
      g_variant_new("(s)", kUuid), G_VARIANT_TYPE("(b)"), G_DBUS_CALL_FLAGS_NONE, 5000, nullptr,
      [](GObject* object, GAsyncResult* result, gpointer data) {
        std::unique_ptr<std::function<void()>> cb(static_cast<std::function<void()>*>(data));
        g_autoptr(GError) error = nullptr;
        g_autoptr(GVariant) reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(object), result, &error);
        gboolean enabled = FALSE; if (reply) g_variant_get(reply, "(b)", &enabled);
        if (!enabled) { needs_relogin = true; PreserveEnabled(); }
        if (error && !g_dbus_error_is_remote_error(error)) error_text = error->message;
        ShellInfo(std::move(*cb));
      }, callback);
}
}  // namespace

bool mvd_gnome_context() { return mvd::GnomeWayland(g_getenv("XDG_CURRENT_DESKTOP"), g_getenv("XDG_SESSION_TYPE")); }
void mvd_gnome_start() {
  if (watcher || !mvd_gnome_context()) return;
  watcher = g_bus_watch_name(G_BUS_TYPE_SESSION, kName, G_BUS_NAME_WATCHER_FLAGS_NONE,
      [](GDBusConnection* connection, const char*, const char* unique, gpointer) {
        ++generation; owner = unique; g_set_object(&bus, connection);
        if (subscription) g_dbus_connection_signal_unsubscribe(bus, subscription);
        subscription = g_dbus_connection_signal_subscribe(bus, owner.c_str(), kName, "Changed", kPath,
            nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
            [](GDBusConnection*, const char*, const char*, const char*, const char*, GVariant* args, gpointer) {
              const char* json = nullptr; g_variant_get(args, "(&s)", &json);
              g_autoptr(FlJsonMessageCodec) codec = fl_json_message_codec_new();
              g_autoptr(FlValue) value = fl_json_message_codec_decode(codec, json, nullptr);
              ApplyCapabilities(value);
            }, nullptr, nullptr);
        Call("GetCapabilities", nullptr, [](FlValue* value, const char* error) {
          if (error) { error_text = error; return; }
          ApplyCapabilities(value);
          for (const auto& entry : windows) Register(entry.first);
          mvd_gnome_following(following);
        });
      }, [](GDBusConnection* connection, const char*, gpointer) {
        ++generation; owner.clear(); g_set_object(&bus, connection);
        if (subscription && bus) g_dbus_connection_signal_unsubscribe(bus, subscription);
        subscription = 0; Replace(capabilities, nullptr); Replace(shell_cursor, nullptr); loaded_version = protocol_version = 0;
        UpdateState();
        for (auto& entry : windows) {
          auto& w = *entry.second; w.registered = w.placing = w.placed = false;
          SetBounds(w, nullptr); gtk_widget_hide(GTK_WIDGET(w.widget));
        }
      }, nullptr, nullptr);
}
void mvd_gnome_shutdown() {
  ++generation;
  if (watcher) g_bus_unwatch_name(watcher);
  watcher = 0;
  if (subscription && bus) g_dbus_connection_signal_unsubscribe(bus, subscription);
  subscription = 0;
  owner.clear(); Replace(capabilities, nullptr); Replace(shell_cursor, nullptr);
  for (auto& entry : windows) gtk_widget_hide(GTK_WIDGET(entry.second->widget));
  windows.clear();
  g_clear_object(&bus);
}
bool mvd_gnome_available() { mvd_gnome_start(); return !g_getenv("POMODOIST_GNOME_XWAYLAND_UNAVAILABLE") && Active() && !Suppressed(); }
const char* mvd_gnome_reason() {
  if (g_getenv("POMODOIST_GNOME_XWAYLAND_UNAVAILABLE")) return "gnomeXWaylandUnavailable";
  if (global_disabled) return "gnomeUserExtensionsDisabled";
  if (Suppressed()) return "gnomeShellSuppressed";
  if (extension_state == "incompatible") return "gnomeExtensionIncompatible";
  if (extension_state == "reloginRequired") return "gnomeExtensionReloginRequired";
  if (extension_state == "disabled") return "gnomeExtensionDisabled";
  if (extension_state == "error") return "gnomeExtensionError";
  if (extension_state == "active") return "displayUnavailable";
  return "gnomeExtensionNotInstalled";
}
void mvd_gnome_environment(FlValue* result) {
  String(result, "placementBackend", "gnomeShell");
  String(result, "gnomeExtensionState", extension_state.c_str());
  const int version = loaded_version ? loaded_version : installed_version;
  if (version) fl_value_set_string_take(result, "gnomeExtensionVersion", fl_value_new_int(version));
  if (!shell_version.empty()) String(result, "gnomeShellVersion", shell_version.c_str());
  if (!error_text.empty()) String(result, "gnomeExtensionError", error_text.c_str());
  if (Active()) {
    FlValue* displays = Field(capabilities, "displays");
    if (displays && fl_value_get_type(displays) == FL_VALUE_TYPE_LIST) fl_value_set_string(result, "displays", displays);
    String(result, "primaryDisplayId", Text(capabilities, "primaryDisplayId"));
  } else {
    fl_value_set_string_take(result, "displays", fl_value_new_list());
    String(result, "primaryDisplayId", "");
  }
}
FlValue* mvd_gnome_cursor() {
  if (!mvd_gnome_available()) return nullptr;
  return shell_cursor ? fl_value_ref(shell_cursor) : nullptr;
}
void mvd_gnome_status(std::function<void()> done) {
  mvd_gnome_start();
  ShellInfo([done = std::move(done)]() mutable {
    ShellVersion([done = std::move(done)]() mutable {
      if (owner.empty()) { done(); return; }
      // Shell's display-config proxy can become ready after we first acquire
      // the bus name, before any registered owner can receive Changed signals.
      Call("GetCapabilities", nullptr, [done = std::move(done)](FlValue* value, const char* error) {
        const bool was_active = Active();
        if (error) { error_text = error; extension_state = "error"; }
        else ApplyCapabilities(value);
        if (!was_active && Active()) {
          for (const auto& entry : windows) Register(entry.first);
          mvd_gnome_following(following);
        }
        done();
      });
    });
  });
}
namespace {
void InstallArchive(std::function<void()> done) {
  g_autofree char* executable = g_file_read_link("/proc/self/exe", nullptr);
  g_autofree char* directory = executable ? g_path_get_dirname(executable) : nullptr;
  g_autofree char* archive = directory ? g_build_filename(directory, "data", "gnome-extension", "pomo@pomodoist.com.shell-extension.zip", nullptr) : nullptr;
  if (!archive || !g_file_test(archive, G_FILE_TEST_IS_REGULAR)) {
    extension_state = "error"; error_text = "Bundled GNOME extension archive unavailable"; done(); return;
  }
  g_autoptr(GError) error = nullptr;
  const char* argv[] = {"gnome-extensions", "install", "--force", archive, nullptr};
  GSubprocess* process = g_subprocess_newv(argv, G_SUBPROCESS_FLAGS_STDOUT_SILENCE, &error);
  if (!process) { extension_state = "error"; error_text = error->message; done(); return; }
  struct Install { GSubprocess* process; std::function<void()> callback; };
  auto* pending = new Install{process, std::move(done)};
  g_subprocess_wait_check_async(process, nullptr, [](GObject*, GAsyncResult* result, gpointer data) {
    std::unique_ptr<Install> p(static_cast<Install*>(data));
    g_autoptr(GError) failure = nullptr;
    bool ok = g_subprocess_wait_check_finish(p->process, result, &failure);
    g_object_unref(p->process);
    if (!ok) { extension_state = "error"; error_text = failure->message; p->callback(); return; }
    installed = true; needs_relogin = true; PreserveEnabled(); Enable(std::move(p->callback));
  }, pending);
}
}  // namespace
void mvd_gnome_install(bool install, std::function<void()> done) {
  mvd_gnome_status([install, done = std::move(done)]() mutable {
    if (shell_version.empty() || !mvd::SupportedGnomeShell(shell_version)) { done(); return; }
    error_text.clear();
    if (install) InstallArchive(std::move(done));
    else Enable(std::move(done));
  });
}

void mvd_gnome_following(bool enabled, std::function<void(const char*)> done) {
  following = enabled;
  const unsigned request = ++following_request;
  Replace(shell_cursor, nullptr);
  if (!Active() || !bus) {
    if (done) done(enabled ? "GNOME pointer source unavailable" : nullptr);
    return;
  }
  struct Following { unsigned epoch; unsigned request; bool enabled; gint64 deadline; std::function<void(const char*)> callback; };
  auto* pending = new Following{generation, request, enabled, g_get_monotonic_time() + 5000000, std::move(done)};
  g_dbus_connection_call(bus, owner.c_str(), kPath, kName, "SetFollowing", g_variant_new("(b)", enabled),
      G_VARIANT_TYPE("()"), G_DBUS_CALL_FLAGS_NONE, 3000, nullptr,
      [](GObject* object, GAsyncResult* result, gpointer data) {
        std::unique_ptr<Following> p(static_cast<Following*>(data));
        g_autoptr(GError) error = nullptr;
        [[maybe_unused]] g_autoptr(GVariant) reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(object), result, &error);
        const char* failure = p->epoch != generation || p->request != following_request ?
            "GNOME pointer lease changed" : error ? error->message : nullptr;
        if (!p->callback) return;
        if (failure || !p->enabled || shell_cursor) { p->callback(failure); return; }
        // RegisterWindow may still be waiting for the first Meta map when the
        // lease is acknowledged. Keep Dart's serialized acquisition pending
        // until its first usable sample rather than failing the first poll.
        g_timeout_add_full(G_PRIORITY_DEFAULT, 20, [](gpointer data) -> gboolean {
          auto* wait = static_cast<Following*>(data);
          const char* failure = wait->epoch != generation || wait->request != following_request ?
              "GNOME pointer lease changed" : !Active() || Suppressed() ? "GNOME pointer source unavailable" :
              g_get_monotonic_time() >= wait->deadline ? "GNOME pointer sample unavailable" : nullptr;
          if (!failure && !shell_cursor) return G_SOURCE_CONTINUE;
          wait->callback(failure); return G_SOURCE_REMOVE;
        }, p.release(), [](gpointer data) { delete static_cast<Following*>(data); });
      }, pending);
}
void mvd_gnome_register_token(const char* token, const char* role, Result done) {
  Call("RegisterWindow", g_variant_new("(ss)", token, role), std::move(done));
}
bool mvd_gnome_command_is_local(const char* method, FlValue* payload, bool registered) {
  if (g_str_equal(method, "bounds")) return !registered;
  if (!g_str_equal(method, "configure")) return false;
  for (const char* key : {"x", "y", "width", "height", "displayId"})
    if (Field(payload, key)) return false;
  return true;
}
void mvd_gnome_token_command(const char* token, const char* method, FlValue* payload, Result done, bool registered) {
  if (mvd_gnome_command_is_local(method, payload, registered)) {
    if (done) done(nullptr, nullptr);
    return;
  }
  Command(token, method, payload, std::move(done));
}
void mvd_gnome_prepare(GtkWindow* window, const char* role) {
  if (!mvd_gnome_context()) return;
  g_return_if_fail(mvd::ValidGnomeRole(role ? role : ""));
  mvd_gnome_start();
  g_autofree char* uuid = g_uuid_string_random();
  std::string token = uuid;
  auto state = std::make_unique<Window>(); state->widget = window; state->role = role;
  windows[token] = std::move(state);
  g_object_set_data_full(G_OBJECT(window), "mvd-gnome-token", g_strdup(token.c_str()), g_free);
  std::string identity = "pomodoist-pomo:" + std::string(role) + ":" + token;
  gtk_window_set_role(window, identity.c_str());
  gtk_widget_set_opacity(GTK_WIDGET(window), 0);
  g_signal_connect(window, "destroy", G_CALLBACK(+[](GtkWidget* widget, gpointer) {
    std::string token = Token(GTK_WINDOW(widget));
    Command(token, "detach", nullptr, nullptr); windows.erase(token);
  }), nullptr);
  Register(token);
}
bool mvd_gnome_window(GtkWindow* window) { return window && !Token(window).empty(); }
bool mvd_gnome_show(GtkWindow* window) {
  auto it = windows.find(Token(window)); if (it == windows.end()) return false;
  it->second->intent = true;
  if (!it->second->registered) Register(it->first);
  Reconcile(it->first); return true;
}
void mvd_gnome_hide(GtkWindow* window) {
  auto it = windows.find(Token(window)); if (it == windows.end()) return;
  it->second->intent = false;
  it->second->placed = it->second->placing = false;
  SetBounds(*it->second, nullptr);
  gtk_widget_hide(GTK_WIDGET(window));
  Command(it->first, "dragEnd", nullptr, nullptr);
}
FlValue* mvd_gnome_bounds(GtkWindow* window) {
  auto it = windows.find(Token(window));
  return it != windows.end() && it->second->bounds ? fl_value_ref(it->second->bounds) : nullptr;
}
void mvd_gnome_configure(GtkWindow* window, FlValue* payload) {
  auto it = windows.find(Token(window)); if (it == windows.end()) return;
  MergeGeometry(it->second->desired, payload);
  ++it->second->desired_revision;
  it->second->placed = false; Reconcile(it->first);
}
void mvd_gnome_command(GtkWindow* window, const char* method, FlValue* payload, Result done) {
  const std::string token = Token(window);
  auto found = windows.find(token);
  if (found == windows.end()) {
    if (done) done(nullptr, "GNOME Pomo surface unavailable");
    return;
  }
  if (mvd_gnome_command_is_local(method, payload, found->second->registered)) {
    if (done) done(nullptr, nullptr);
    return;
  }
  const bool cleanup = g_str_equal(method, "detach") || g_str_equal(method, "dragEnd");
  if (g_str_equal(method, "detach")) {
    ++found->second->session_revision;
    auto& w = *found->second;
    w.intent = w.registered = w.placed = w.placing = false;
    SetBounds(w, nullptr); gtk_widget_hide(GTK_WIDGET(w.widget));
  }
  if (!Active() || Suppressed()) {
    if (done) done(nullptr, cleanup ? nullptr : "GNOME Pomo surface unavailable");
    return;
  }
  const bool geometry = g_str_equal(method, "configure") || g_str_equal(method, "move");
  if (geometry && payload) {
    ++windows[token]->desired_revision;
    auto& desired = windows[token]->desired;
    MergeGeometry(desired, payload);
  }
  if (geometry && (!windows[token]->registered || !windows[token]->bounds)) {
    // Flutter configures utility windows before its first show. Retain that
    // intent locally until Shell attaches the mapped Meta.Window.
    windows[token]->placed = false;
    if (done) done(nullptr, nullptr);
    return;
  }
  const bool reads_bounds = geometry || g_str_equal(method, "bounds");
  const unsigned revision = windows[token]->desired_revision;
  const unsigned session = windows[token]->session_revision;
  mvd_gnome_token_command(token.c_str(), method, payload, [token, geometry, reads_bounds, revision, session, done = std::move(done)](FlValue* value, const char* error) {
    auto it = windows.find(token);
    if (it != windows.end() && it->second->session_revision != session) {
      if (done) done(nullptr, "Pomo window session changed");
      return;
    }
    if (!error && it != windows.end() && reads_bounds) {
      SetBounds(*it->second, value);
      if (geometry) it->second->placed = it->second->bounds && revision == it->second->desired_revision;
      Reconcile(token);
    }
    if (done) done(value, error);
  }, found->second->registered);
}
