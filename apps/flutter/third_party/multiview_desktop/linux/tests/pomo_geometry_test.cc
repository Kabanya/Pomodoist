#include "../mvd_linux_pomo_geometry.h"
#include "../mvd_linux_pomo_identity.h"
#include "../mvd_linux_pomo_drag_state.h"
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
  // Output loss retains local margins, clamped to the replacement usable box.
  const auto fallback = mvd::ClampLayerMargins(800, 600, 328, 328, {952, 426});
  assert(fallback.left == 472 && fallback.top == 272);
  const auto small_fallback = mvd::ClampLayerMargins(200, 200, 328, 328, {-20, -10});
  assert(small_fallback.left == 0 && small_fallback.top == 0);
  const auto fractional = mvd::LayerPlacement(1920, -1080, 1930.6, -1059.6);
  assert(fractional.left == 11 && fractional.top == 20);
  // GTK 3 can keep stale logical origins after a live output rearrangement.
  // The independent xdg-output v2 stream commits each output atomically on done.
  mvd::LogicalOutputState logical;
  assert(!logical.Get().ready);
  logical.Position(1280, 0); logical.Size(1280, 800); logical.Name("HEADLESS-1");
  assert(!logical.Get().ready);  // No half-applied descriptor before done.
  logical.Done();
  assert(logical.Get().ready && logical.Get().geometry.x == 1280);
  assert(logical.Get().geometry.width == 1280 && logical.Get().name == "HEADLESS-1");
  logical.Position(-1920, -1080); logical.Size(1920, 1080);
  assert(logical.Get().geometry.x == 1280 && logical.Get().geometry.width == 1280);
  logical.Done();
  assert(logical.Get().geometry.x == -1920 && logical.Get().geometry.y == -1080);
  assert(logical.Get().geometry.width == 1920 && logical.Get().geometry.height == 1080);
  assert(logical.Get().name == "HEADLESS-1");
  logical.Size(0, 1080); logical.Done(); assert(!logical.Get().ready);

  // GDK reports the whole output on native Wayland. Compositor-configured
  // extent, not that full height, must bound both saved placement and dragging.
  const auto usable = mvd::MeasuredLayerWorkArea(0, 0, 1280, 800, 1280, 754);
  assert(usable.x == 0 && usable.y == 0 && usable.width == 1280 && usable.height == 754);
  const auto bottom = mvd::ClampPomoDragPosition(usable.x, usable.y, usable.width,
      usable.height, 328, 328, 928, 448);
  assert(bottom.x == 928 && bottom.y == 426);
  const auto usable_margin = mvd::LayerPlacement(usable.x, usable.y, bottom.x, bottom.y);
  assert(usable_margin.left == 928 && usable_margin.top == 426);
  // A top/left reserved panel is already applied by layer-shell. Coordinates
  // remain relative to the usable box; do not add an invented global offset.
  const auto other = mvd::MeasuredLayerWorkArea(-1280, -800, 1280, 800, 1230, 745);
  assert(other.x == -1280 && other.y == -800 && other.width == 1230 && other.height == 745);
  const auto other_bottom = mvd::ClampPomoDragPosition(other.x, other.y, other.width,
      other.height, 328, 328, -20, -10);
  assert(other_bottom.x == -378 && other_bottom.y == -383);
  assert(mvd::MeasuredLayerWorkArea(0, 0, 1280, 800, 0, 754).width == 0);
  assert(mvd::MeasuredLayerWorkArea(0, 0, 1280, 800, 1280, 801).height == 0);
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
