#include "../mvd_linux_gnome_policy.h"
#include "../mvd_linux_pomo_geometry.h"
#include <cassert>
#include <vector>
int main() {
  using namespace mvd;
  assert(ValidGnomeRole("companion"));
  assert(ValidGnomeRole("settings"));
  assert(!ValidGnomeRole("window"));
  assert(!ValidGnomeRole(""));
  assert(GnomeStartupBackend("GNOME", "wayland", true) == StartupBackend::x11);
  assert(GnomeStartupBackend("GNOME", "wayland", false) == StartupBackend::wayland);
  assert(GnomeStartupBackend("KDE", "wayland", true) == StartupBackend::unchanged);
  assert(GnomeStartupBackend("GNOME", "x11", true) == StartupBackend::unchanged);
  assert(SupportedGnomeShell("46.0"));
  assert(SupportedGnomeShell("50.beta"));
  assert(SupportedGnomeShell("51"));
  assert(!SupportedGnomeShell("49.0"));
  assert(!SupportedGnomeShell("52.0"));
  assert(!SupportedGnomeShell("unknown"));
  assert(GnomeWayland("ubuntu:GNOME", "wayland"));
  assert(!GnomeWayland("KDE", "wayland"));
  assert(!GnomeWayland("GNOME", "x11"));
  assert(ExtensionState(true, 1, 1, true, false, false) == "active");
  assert(ExtensionState(true, 2, 1, true, false, false) == "incompatible");
  assert(ExtensionState(true, 1, 0, true, true, false) == "reloginRequired");
  assert(ExtensionState(false, 0, 0, false, false, false) == "notInstalled");
  assert(ExtensionState(false, 0, 1, true, false, false) == "disabled");
  assert(ExtensionState(false, 0, 1, true, true, false) == "reloginRequired");
  assert(ExtensionState(true, 1, 1, true, false, true) == "disabled");
  assert(GnomePlacement(true, false, true, false, false, false, false) == GnomePlacementAction::map);
  assert(GnomePlacement(true, false, true, true, false, false, false) == GnomePlacementAction::map);
  assert(GnomePlacement(true, false, true, true, true, false, false) == GnomePlacementAction::place);
  assert(GnomePlacement(true, false, true, true, true, false, true) == GnomePlacementAction::wait);
  assert(GnomePlacement(true, false, true, true, true, true, false) == GnomePlacementAction::reveal);
  assert(GnomePlacement(true, true, true, true, true, true, false) == GnomePlacementAction::hide);
  assert(GnomePlacement(false, false, true, true, true, true, false) == GnomePlacementAction::hide);
  assert(GnomePlacement(true, false, false, true, true, true, false) == GnomePlacementAction::wait);
  auto local = ViewportInputShape({100, 50, 200, 80, true, false}, 1000, 500, 800, 400);
  assert(local.x == 80 && local.y == 40 && local.width == 160 && local.height == 64);
  auto pending = ViewportInputShape({100, 50, 200, 80, true, false}, 0, 500, 800, 400);
  assert(InputRectangles(pending).empty());
  auto enabled = EnableUuid({"other@example.com", "pomo@pomodoist.com"});
  assert(enabled.size() == 2 && enabled[0] == "other@example.com");
  auto appended = EnableUuid({"other@example.com"});
  assert(appended.size() == 2 && appended[1] == "pomo@pomodoist.com");
}
