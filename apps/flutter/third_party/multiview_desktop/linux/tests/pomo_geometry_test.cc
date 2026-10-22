#include "../mvd_linux_pomo_geometry.h"
#include "../mvd_linux_pomo_identity.h"
#include <cassert>
#include <limits>

static bool Contains(const std::vector<mvd::InputRectangle>& rects, int x, int y) {
  for (const auto& r : rects) {
    if (x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height) return true;
  }
  return false;
}

int main() {
  const std::string monitor = "Maker:Panel:600x340";
  assert(mvd::AvailableMonitorId(monitor, {}) == monitor);
  assert(mvd::AvailableMonitorId(monitor, {monitor}) == monitor + ":2");
  // After unplugging the sole monitor, its old GdkMonitor is no longer in the
  // connected set. Reconnection must recover the saved base identifier.
  assert(mvd::AvailableMonitorId(monitor, {}) == monitor);
  // A connected identical panel keeps its suffix; the freed base is reusable.
  assert(mvd::AvailableMonitorId(monitor, {monitor + ":2"}) == monitor);
  assert(mvd::AvailableMonitorId(monitor, {monitor, monitor + ":3"}) == monitor + ":2");

  // The monitor may be left of the primary display and have a reserved panel.
  const auto placement = mvd::LayerPlacement(-1920, 32, -1800, 92);
  assert(placement.left == 120 && placement.top == 60);
  const auto fractional = mvd::LayerPlacement(1920, -1080, 1930.6, -1059.6);
  assert(fractional.left == 11 && fractional.top == 20);
  const auto rect = mvd::InputRectangles({10, 20, 48, 48, true, false});
  assert(rect.size() == 1 && rect[0].x == 10 && rect[0].width == 48);
  const auto ellipse = mvd::InputRectangles({0, 0, 48, 48, false, false});
  assert(!Contains(ellipse, 0, 0));
  assert(Contains(ellipse, 24, 0));
  assert(Contains(ellipse, 0, 24));
  assert(!Contains(ellipse, 48, 24));
  const auto capsule = mvd::InputRectangles({0, 0, 120, 48, false, true});
  assert(!Contains(capsule, 0, 0));
  assert(Contains(capsule, 60, 0));
  assert(Contains(capsule, 119, 24));
  assert(mvd::InputRectangles({0, 0, -2, 48, true, false}).empty());
  assert(mvd::InputRectangles({0, 0, 0, 48, true, false}).empty());
  assert(mvd::InputRectangles({0, 0, std::numeric_limits<double>::infinity(), 48, true, false}).empty());
}
