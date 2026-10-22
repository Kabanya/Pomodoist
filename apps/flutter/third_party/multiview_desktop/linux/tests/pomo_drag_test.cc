#include "../mvd_linux_pomo_drag_state.h"

#include <cassert>
#include <initializer_list>
#include <cmath>
#include <limits>

int main() {
  // Native visuals stay inside the selected monitor's work area while the raw
  // sampler remains available for a post-release output handoff.
  const auto clamped = mvd::ClampPomoDragPosition(-1920, 32, 1920, 1048,
      300, 250, -100, -50);
  assert(clamped.x == -300 && clamped.y == 32);
  const auto oversized = mvd::ClampPomoDragPosition(0, 24, 200, 100,
      300, 250, 500, 600);
  assert(oversized.x == 0 && oversized.y == 24);
  const auto within = mvd::ClampPomoDragPosition(1920, 0, 2560, 1440,
      300, 250, 2100.25, 500.5);
  assert(within.x == 2100.25 && within.y == 500.5);
  mvd::PomoDragState drag;
  double x = 0, y = 0;
  assert(!drag.Position(&x, &y));
  // Reproduce the feedback: the compositor still exposes origin 100 while
  // Dart has already committed its requested origin 103. Surface-local pointer
  // x is 13 (physical screen x 113), with a grab anchor of 10. The old host
  // formula jumps to 106, then back to 103 when the compositor catches up.
  assert(drag.BeginRelative(100, 0));
  assert(drag.AddRelative(3, 0));
  assert(drag.Position(&x, &y) && x == 103);
  const double old_feedback_position = 103 + 13 - 10;
  assert(old_feedback_position == 106 && old_feedback_position != x);
  // A surface reposition may emit absolute pointer motion without physical
  // relative motion. Such a notification must leave the requested origin alone.
  assert(drag.AddRelative(0, 0));
  assert(drag.Position(&x, &y) && x == 103);
  assert(drag.BeginRelative(100, -40));
  assert(drag.AddRelative(3.25, -1.5));
  assert(drag.Position(&x, &y) && x == 103.25 && y == -41.5);
  // Committing the window at rounded or delayed compositor origins must never
  // become an input to relative pointer accumulation.
  for (double compositor_origin : {100.0, 103.0, 100.0, 250.0}) {
    (void)compositor_origin;
    assert(drag.AddRelative(.25, .5));
  }
  assert(drag.Position(&x, &y) && x == 104.25 && y == -39.5);
  assert(!drag.AddRelative(std::numeric_limits<double>::quiet_NaN(), 1));
  assert(drag.Position(&x, &y) && x == 104.25 && y == -39.5);
  drag.End();
  assert(!drag.Position(&x, &y));
  assert(!drag.AddRelative(100, 100));

  // X11 absolute sampling is anchored once and cannot drift after native moves.
  assert(drag.BeginAbsolute(-1920, 20, -1800, 100));
  assert(drag.SampleAbsolute(-1790, 105));
  assert(drag.Position(&x, &y) && x == -1910 && y == 25);
  assert(drag.SampleAbsolute(-1790, 105));
  assert(drag.Position(&x, &y) && x == -1910 && y == 25);
  assert(!drag.AddRelative(10, 10));
  assert(drag.SampleAbsolute(-1800, 100));
  assert(drag.Position(&x, &y) && x == -1920 && y == 20);
  drag.End();
  assert(drag.BeginRelative(500, 600));
  assert(drag.Position(&x, &y) && x == 500 && y == 600);
  drag.End();
  assert(!drag.BeginRelative(std::numeric_limits<double>::infinity(), 0));
  assert(!drag.Position(&x, &y));
}
