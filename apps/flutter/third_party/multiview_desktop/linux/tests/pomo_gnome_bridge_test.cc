#include "../mvd_linux_gnome.h"
#include <gio/gio.h>
#include <glib/gstdio.h>
#include <cassert>
#include <functional>
#include <string>
namespace {
const char* kName = "com.pomodoist.Pomo.Gnome1";
const char* kPath = "/com/pomodoist/Pomo/Gnome1";
std::string capabilities = R"({"protocolVersion":1,"extensionVersion":1,"shellVersion":"46.0","supported":true,"suppressed":false,"displays":[{"id":"gnome:DP-1","name":"Monitor","x":0,"y":0,"width":1920,"height":1080,"workX":0,"workY":32,"workWidth":1920,"workHeight":1048,"scale":1.25}],"primaryDisplayId":"gnome:DP-1"})";
bool lease = false;
int capability_calls = 0;
int command_calls = 0;
bool extension_known = false;
bool enable_succeeds = false;
int extension_disk_version = 1;
std::string shell_version = "46.0";
std::string destination;
GDBusMethodInvocation* held_command = nullptr;
bool hold_command = false;
bool delay_lease = false;
GDBusMethodInvocation* held_lease = nullptr;
void Pump(std::function<bool()> condition, const char* label = "condition") {
  gint64 deadline = g_get_monotonic_time() + 5000000;
  while (!condition() && g_get_monotonic_time() < deadline) {
    while (g_main_context_iteration(nullptr, FALSE)) {}
    g_usleep(1000);
  }
  if (!condition()) g_printerr("Timed out waiting for %s\n", label);
  assert(condition());
}
void Own(GDBusConnection* bus, const char* name, bool acquire) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(bus, "org.freedesktop.DBus",
      "/org/freedesktop/DBus", "org.freedesktop.DBus", acquire ? "RequestName" : "ReleaseName",
      acquire ? g_variant_new("(su)", name, 0) : g_variant_new("(s)", name),
      nullptr, G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, &error);
  assert(reply && !error);
}
std::string State() {
  g_autoptr(FlValue) environment = fl_value_new_map();
  mvd_gnome_environment(environment);
  return fl_value_get_string(fl_value_lookup_string(environment, "gnomeExtensionState"));
}
void Changed(GDBusConnection* bus, const char* json) {
  g_autoptr(GError) error = nullptr;
  g_dbus_connection_emit_signal(bus, destination.c_str(), kPath, kName, "Changed", g_variant_new("(s)", json), &error);
  assert(!error);
}
}
int main() {
  g_setenv("XDG_CURRENT_DESKTOP", "ubuntu:GNOME", TRUE);
  g_setenv("XDG_SESSION_TYPE", "wayland", TRUE);
  g_autoptr(GTestDBus) fixture = g_test_dbus_new(G_TEST_DBUS_NONE);
  g_test_dbus_up(fixture);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) service = g_dbus_connection_new_for_address_sync(
      g_test_dbus_get_bus_address(fixture), static_cast<GDBusConnectionFlags>(
          G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT | G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION),
      nullptr, nullptr, &error);
  assert(service && !error);
  const char* xml = R"(<node><interface name="com.pomodoist.Pomo.Gnome1"><method name="GetCapabilities"><arg type="s" direction="out"/></method><method name="RegisterWindow"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="out"/></method><method name="Command"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="out"/></method><method name="SetFollowing"><arg type="b" direction="in"/></method><signal name="Changed"><arg type="s"/></signal></interface></node>)";
  g_autoptr(GDBusNodeInfo) info = g_dbus_node_info_new_for_xml(xml, nullptr);
  GDBusInterfaceVTable table{};
  table.method_call = [](GDBusConnection*, const char* sender, const char*, const char*, const char* method,
      GVariant* args, GDBusMethodInvocation* invocation, gpointer) {
    destination = sender;
    if (g_str_equal(method, "GetCapabilities")) {
      ++capability_calls;
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(s)", capabilities.c_str()));
    }
    else if (g_str_equal(method, "RegisterWindow")) {
      const char *token, *role; g_variant_get(args, "(&s&s)", &token, &role);
      assert(std::string(token) == "pending-token" && std::string(role) == "companion");
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(s)", "{\"ready\":false}"));
    } else if (g_str_equal(method, "Command")) {
      const char *token, *command, *json; g_variant_get(args, "(&s&s&s)", &token, &command, &json);
      ++command_calls;
      assert(std::string(token) == "pending-token");
      if (std::string(command) == "configure") {
        g_autoptr(FlJsonMessageCodec) codec = fl_json_message_codec_new();
        g_autoptr(FlValue) payload = fl_json_message_codec_decode(codec, json, nullptr);
        assert(payload && fl_value_get_length(payload) == 1);
        assert(fl_value_get_float(fl_value_lookup_string(payload, "width")) == 321);
        assert(!fl_value_lookup_string(payload, "regions") && !fl_value_lookup_string(payload, "viewId"));
      }
      if (std::string(command) != "move") {
        g_dbus_method_invocation_return_value(invocation, g_variant_new("(s)", "null"));
        return;
      }
      g_autoptr(FlJsonMessageCodec) codec = fl_json_message_codec_new();
      g_autoptr(FlValue) payload = fl_json_message_codec_decode(codec, json, nullptr);
      assert(payload && fl_value_get_float(fl_value_lookup_string(payload, "x")) == 3.25);
      if (hold_command) held_command = G_DBUS_METHOD_INVOCATION(g_object_ref(invocation));
      else g_dbus_method_invocation_return_value(invocation, g_variant_new("(s)", "{\"x\":3.25,\"y\":5,\"width\":300,\"height\":200,\"scale\":1.25,\"displayId\":\"gnome:DP-1\"}"));
    } else {
      gboolean enabled = FALSE; g_variant_get(args, "(b)", &enabled); lease = enabled;
      if (enabled && delay_lease) held_lease = G_DBUS_METHOD_INVOCATION(g_object_ref(invocation));
      else g_dbus_method_invocation_return_value(invocation, nullptr);
    }
  };
  guint registration = g_dbus_connection_register_object(service, kPath, info->interfaces[0], &table, nullptr, nullptr, &error);
  assert(registration && !error);
  const char* shell_xml = R"(<node><interface name="org.gnome.Shell.Extensions"><method name="GetExtensionInfo"><arg type="s" direction="in"/><arg type="a{sv}" direction="out"/></method><method name="EnableExtension"><arg type="s" direction="in"/><arg type="b" direction="out"/></method></interface><interface name="org.gnome.Shell"><property name="ShellVersion" type="s" access="read"/></interface></node>)";
  g_autoptr(GDBusNodeInfo) shell_info = g_dbus_node_info_new_for_xml(shell_xml, nullptr);
  GDBusInterfaceVTable shell_table{};
  shell_table.method_call = [](GDBusConnection*, const char*, const char*, const char*, const char* method,
      GVariant* args, GDBusMethodInvocation* invocation, gpointer) {
    const char* uuid = nullptr; g_variant_get(args, "(&s)", &uuid);
    assert(std::string(uuid) == "pomo@pomodoist.com");
    if (g_str_equal(method, "EnableExtension")) {
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(b)", enable_succeeds));
    } else {
      GVariantBuilder builder; g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
      if (extension_known) {
        g_variant_builder_add(&builder, "{sv}", "state", g_variant_new_double(2));
        g_variant_builder_add(&builder, "{sv}", "version", g_variant_new_double(extension_disk_version));
      }
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(a{sv})", &builder));
    }
  };
  guint shell_registration = g_dbus_connection_register_object(service, "/org/gnome/Shell", shell_info->interfaces[0], &shell_table, nullptr, nullptr, &error);
  assert(shell_registration && !error);
  GDBusInterfaceVTable property_table{};
  property_table.get_property = [](GDBusConnection*, const char*, const char*, const char*, const char* property, GError**, gpointer) -> GVariant* {
    assert(std::string(property) == "ShellVersion");
    return g_variant_new_string(shell_version.c_str());
  };
  guint property_registration = g_dbus_connection_register_object(service, "/org/gnome/Shell", shell_info->interfaces[1], &property_table, nullptr, nullptr, &error);
  assert(property_registration && !error);
  Own(service, "org.gnome.Shell", true);
  Own(service, kName, true);
  const std::string ready_capabilities = capabilities;
  capabilities = R"({"protocolVersion":1,"extensionVersion":1,"shellVersion":"46.0","supported":false,"suppressed":false,"displays":[],"primaryDisplayId":""})";
  mvd_gnome_start();
  Pump([] { return capability_calls > 0 && State() == "active"; }, "initial empty topology");
  assert(!mvd_gnome_available());
  assert(std::string(mvd_gnome_reason()) == "displayUnavailable");
  capabilities = ready_capabilities;
  bool initial_refreshed = false;
  mvd_gnome_status([&] { initial_refreshed = true; });
  Pump([&] { return initial_refreshed; }, "topology refresh without owner change");
  assert(mvd_gnome_available());
  assert(State() == "active");
  g_setenv("POMODOIST_GNOME_XWAYLAND_UNAVAILABLE", "1", TRUE);
  assert(!mvd_gnome_available());
  assert(std::string(mvd_gnome_reason()) == "gnomeXWaylandUnavailable");
  g_unsetenv("POMODOIST_GNOME_XWAYLAND_UNAVAILABLE");
  const int commands_before_pending_bounds = command_calls;
  bool pending_bounds_completed = false;
  mvd_gnome_token_command("pending-token", "bounds", nullptr, [&](FlValue* result, const char* failure) {
    assert(!failure && (!result || fl_value_get_type(result) == FL_VALUE_TYPE_NULL)); pending_bounds_completed = true;
  }, false);
  Pump([&] { return pending_bounds_completed; }, "bounds before re-registration");
  assert(command_calls == commands_before_pending_bounds);
  g_autoptr(FlValue) local_input = fl_value_new_map();
  fl_value_set_string_take(local_input, "viewId", fl_value_new_int(15));
  fl_value_set_string_take(local_input, "regions", fl_value_new_list());
  bool local_input_completed = false;
  mvd_gnome_token_command("pending-token", "configure", local_input, [&](FlValue* result, const char* failure) {
    assert(!failure && (!result || fl_value_get_type(result) == FL_VALUE_TYPE_NULL)); local_input_completed = true;
  });
  Pump([&] { return local_input_completed; }, "input-only configure");
  assert(command_calls == commands_before_pending_bounds);
  fl_value_set_string_take(local_input, "width", fl_value_new_float(321));
  bool global_configured = false;
  mvd_gnome_token_command("pending-token", "configure", local_input, [&](FlValue*, const char* failure) {
    assert(!failure); global_configured = true;
  });
  Pump([&] { return global_configured; }, "geometry-only configure payload");
  assert(command_calls == commands_before_pending_bounds + 1);
  bool registered = false;
  mvd_gnome_register_token("pending-token", "companion", [&](FlValue* result, const char* failure) {
    assert(!failure && result);
    assert(!fl_value_get_bool(fl_value_lookup_string(result, "ready")));
    registered = true;
  });
  Pump([&] { return registered; }, "pending window registration");
  g_autoptr(FlValue) move = fl_value_new_map();
  fl_value_set_string_take(move, "x", fl_value_new_float(3.25));
  bool moved = false;
  mvd_gnome_token_command("pending-token", "move", move, [&](FlValue* result, const char* failure) {
    assert(!failure && result);
    assert(fl_value_get_float(fl_value_lookup_string(result, "x")) == 3.25);
    assert(std::string(fl_value_get_string(fl_value_lookup_string(result, "displayId"))) == "gnome:DP-1");
    moved = true;
  });
  Pump([&] { return moved; }, "confirmed command bounds");
  g_autoptr(FlValue) environment = fl_value_new_map();
  mvd_gnome_environment(environment);
  assert(std::string(fl_value_get_string(fl_value_lookup_string(environment, "primaryDisplayId"))) == "gnome:DP-1");
  assert(!mvd_gnome_cursor());
  const char* sample = R"({"protocolVersion":1,"extensionVersion":1,"shellVersion":"46.0","supported":true,"suppressed":false,"displays":[],"primaryDisplayId":"","cursor":{"x":1560.5,"y":47}})";
  delay_lease = true;
  bool acquired = false;
  mvd_gnome_following(true, [&](const char* failure) { assert(!failure); acquired = true; });
  Pump([] { return held_lease != nullptr; }, "delayed lease request");
  assert(lease && !acquired);
  g_dbus_method_invocation_return_value(held_lease, nullptr); g_clear_object(&held_lease);
  for (int i = 0; i < 50; ++i) { while (g_main_context_iteration(nullptr, FALSE)) {} g_usleep(1000); }
  assert(!acquired);  // A lease ACK can precede the companion's first Meta map.
  Changed(service, sample);
  Pump([&] { return acquired; }, "initial pointer sample after lease acknowledgement");
  Pump([] { g_autoptr(FlValue) cursor = mvd_gnome_cursor(); return cursor != nullptr; });
  g_autoptr(FlValue) cursor = mvd_gnome_cursor();
  assert(fl_value_get_float(fl_value_lookup_string(cursor, "x")) == 1560.5);
  g_print("capabilities, following and cursor passed\n");
  Changed(service, R"({"protocolVersion":1,"extensionVersion":1,"shellVersion":"46.0","supported":true,"suppressed":false,"displays":[],"primaryDisplayId":"","windows":{}})");
  // Drain the signal without relying on another pointer motion.
  for (int i = 0; i < 50; ++i) { while (g_main_context_iteration(nullptr, FALSE)) {} g_usleep(1000); }
  g_autoptr(FlValue) retained_cursor = mvd_gnome_cursor();
  assert(retained_cursor && fl_value_get_float(fl_value_lookup_string(retained_cursor, "x")) == 1560.5);
  // A malformed pointer must never escape to Dart as an unexpected value type.
  Changed(service, R"({"protocolVersion":1,"extensionVersion":1,"supported":true,"suppressed":false,"cursor":"invalid"})");
  Pump([] { g_autoptr(FlValue) cursor = mvd_gnome_cursor(); return cursor == nullptr; });
  Changed(service, R"({"protocolVersion":1,"extensionVersion":1,"supported":true,"suppressed":true,"cursor":{"x":20,"y":30}})");
  Pump([] { return !mvd_gnome_available(); });
  assert(std::string(mvd_gnome_reason()) == "gnomeShellSuppressed");
  assert(!mvd_gnome_cursor());
  bool stale_lease_completed = false;
  mvd_gnome_following(true, [&](const char* failure) { assert(failure); stale_lease_completed = true; });
  Pump([] { return held_lease != nullptr; }, "lease before owner change");
  hold_command = true;
  bool stale_completed = false;
  mvd_gnome_token_command("pending-token", "move", move, [&](FlValue* result, const char* failure) {
    assert(!result && failure); stale_completed = true;
  });
  Pump([] { return held_command != nullptr; }, "in-flight command");
  Own(service, kName, false);
  Pump([] { return State() != "active"; });
  assert(!mvd_gnome_cursor());
  g_dbus_method_invocation_return_value(held_lease, nullptr); g_clear_object(&held_lease);
  Pump([&] { return stale_lease_completed; }, "lease epoch rejection");
  g_dbus_method_invocation_return_value(held_command, g_variant_new("(s)", "{\"x\":900}"));
  g_clear_object(&held_command);
  Pump([&] { return stale_completed; }, "owner generation rejection");
  capabilities = R"({"protocolVersion":2,"extensionVersion":1,"supported":true})";
  Own(service, kName, true);
  Pump([] { return State() == "incompatible"; });
  assert(!mvd_gnome_available());
  g_print("suppression, malformed cursor, owner loss and incompatible protocol passed\n");
  Own(service, kName, false);
  Pump([] { return State() != "active"; });
  bool completed = false;
  mvd_gnome_status([&] { completed = true; }); Pump([&] { return completed; }, "async status/install completion");
  assert(State() == "notInstalled");
  shell_version = "49.0";
  completed = false; mvd_gnome_status([&] { completed = true; }); Pump([&] { return completed; }, "unsupported Shell status");
  assert(State() == "incompatible");
  completed = false; mvd_gnome_install(true, [&] { completed = true; }); Pump([&] { return completed; }, "unsupported Shell install gate");
  assert(State() == "incompatible");
  shell_version = "46.0";
  extension_known = true;
  completed = false; mvd_gnome_status([&] { completed = true; }); Pump([&] { return completed; }, "async status/install completion");
  assert(State() == "disabled");
  extension_disk_version = 2;
  completed = false; mvd_gnome_status([&] { completed = true; }); Pump([&] { return completed; }, "incompatible disk version");
  assert(State() == "incompatible");
  extension_disk_version = 1;
  // Installer runs argv directly, including a bundle path containing spaces.
  g_autofree char* exe = g_file_read_link("/proc/self/exe", nullptr);
  g_autofree char* directory = g_path_get_dirname(exe);
  g_autofree char* resources = g_build_filename(directory, "data", "gnome-extension", nullptr);
  assert(g_mkdir_with_parents(resources, 0700) == 0);
  g_autofree char* archive = g_build_filename(resources, "pomo@pomodoist.com.shell-extension.zip", nullptr);
  assert(g_file_set_contents(archive, "fixture", -1, nullptr));
  g_autofree char* installer = g_build_filename(directory, "gnome-extensions", nullptr);
  const char* script = "#!/bin/sh\n[ \"$#\" = 3 ] && [ \"$1\" = install ] && [ \"$2\" = --force ] && [ -f \"$3\" ] || exit 42\nexit \"${POMO_TEST_INSTALL_EXIT:-0}\"\n";
  assert(g_file_set_contents(installer, script, -1, nullptr));
  assert(g_chmod(installer, 0700) == 0);
  g_setenv("PATH", directory, TRUE);
  extension_known = false;
  completed = false; mvd_gnome_install(true, [&] { completed = true; }); Pump([&] { return completed; }, "async status/install completion");
  assert(State() == "reloginRequired");
  g_print("first install relogin passed\n");
  g_autoptr(GSettings) settings = g_settings_new("org.gnome.shell");
  g_auto(GStrv) enabled = g_settings_get_strv(settings, "enabled-extensions");
  assert(std::string(enabled[0]) == "keep@example.com");
  assert(std::string(enabled[1]) == "pomo@pomodoist.com");
  g_settings_set_boolean(settings, "disable-user-extensions", TRUE);
  completed = false; mvd_gnome_install(false, [&] { completed = true; }); Pump([&] { return completed; }, "async status/install completion");
  assert(State() == "disabled");
  assert(g_settings_get_boolean(settings, "disable-user-extensions"));
  assert(std::string(mvd_gnome_reason()) == "gnomeUserExtensionsDisabled");
  g_settings_set_boolean(settings, "disable-user-extensions", FALSE);
  g_setenv("POMO_TEST_INSTALL_EXIT", "7", TRUE);
  completed = false; mvd_gnome_install(true, [&] { completed = true; }); Pump([&] { return completed; }, "async status/install completion");
  assert(State() == "error");
  // Installing fresh bytes cannot make an already loaded old extension ready.
  g_print("installer failure and global setting preservation passed\n");
  g_setenv("POMO_TEST_INSTALL_EXIT", "0", TRUE);
  capabilities = R"({"protocolVersion":1,"extensionVersion":2,"supported":true,"displays":[]})";
  Own(service, kName, true); Pump([] { return State() == "reloginRequired"; }, "loaded stale bridge");
  completed = false; mvd_gnome_install(true, [&] { completed = true; }); Pump([&] { return completed; }, "async status/install completion");
  assert(State() == "reloginRequired");
  mvd_gnome_shutdown();
  g_dbus_connection_unregister_object(service, shell_registration);
  g_dbus_connection_unregister_object(service, property_registration);
  g_dbus_connection_unregister_object(service, registration);
  g_print("installer argv, relogin, stale loaded version, failure and settings preservation passed\n");
  g_dbus_connection_close_sync(service, nullptr, nullptr);
  g_print("closing fixture\n");
  g_test_dbus_stop(fixture);
  g_print("fixture stopped\n");
}
