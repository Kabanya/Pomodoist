#ifndef MVD_LINUX_GNOME_POLICY_H_
#define MVD_LINUX_GNOME_POLICY_H_
#include <algorithm>
#include <cctype>
#include <string>
#include <vector>
namespace mvd {
inline bool GnomeWayland(const char* desktop, const char* session) {
  std::string name = desktop ? desktop : "";
  std::transform(name.begin(), name.end(), name.begin(), [](unsigned char c) { return std::tolower(c); });
  return session && std::string(session) == "wayland" && name.find("gnome") != std::string::npos;
}
inline bool ValidGnomeRole(const std::string& role) { return role == "companion" || role == "settings"; }
enum class StartupBackend { unchanged, x11, wayland };
inline StartupBackend GnomeStartupBackend(const char* desktop, const char* session, bool x11_available) {
  if (!GnomeWayland(desktop, session)) return StartupBackend::unchanged;
  return x11_available ? StartupBackend::x11 : StartupBackend::wayland;
}
inline bool SupportedGnomeShell(const std::string& version) {
  const auto dot = version.find('.');
  const std::string major = version.substr(0, dot);
  return major == "46" || major == "50" || major == "51";
}
inline std::string ExtensionState(bool bridge, int protocol, int version,
                                  bool installed, bool relogin, bool disabled) {
  if (disabled) return "disabled";
  if (relogin && !(bridge && protocol == 1 && version == 1)) return "reloginRequired";
  if (bridge) return protocol == 1 && version == 1 ? "active" : "incompatible";
  return installed ? "disabled" : "notInstalled";
}
enum class GnomePlacementAction { hide, map, place, reveal, wait };
inline GnomePlacementAction GnomePlacement(bool available, bool suppressed,
    bool intent, bool registered, bool has_bounds, bool placed, bool placing) {
  if (!available || suppressed) return GnomePlacementAction::hide;
  if (!intent) return GnomePlacementAction::wait;
  if (!registered || !has_bounds) return GnomePlacementAction::map;
  if (placed) return GnomePlacementAction::reveal;
  return placing ? GnomePlacementAction::wait : GnomePlacementAction::place;
}
inline std::vector<std::string> EnableUuid(std::vector<std::string> entries) {
  const std::string uuid = "pomo@pomodoist.com";
  if (std::find(entries.begin(), entries.end(), uuid) == entries.end()) entries.push_back(uuid);
  return entries;
}
}
#endif
