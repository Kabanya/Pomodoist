#ifndef MVD_LINUX_POMO_DRAG_STATE_H_
#define MVD_LINUX_POMO_DRAG_STATE_H_

#include <algorithm>
#include <cmath>

namespace mvd {
struct PomoDragPosition { double x, y; };
inline PomoDragPosition ClampPomoDragPosition(
    double work_x, double work_y, double work_width, double work_height,
    double width, double height, double x, double y) {
  return {std::clamp(x, work_x, work_x + std::max(0.0, work_width - width)),
          std::clamp(y, work_y, work_y + std::max(0.0, work_height - height))};
}
// Window/compositor positions are deliberately absent after Begin: only physical
// pointer motion may change this accumulator, preventing surface-motion feedback.
class PomoDragState {
 public:
  bool BeginRelative(double x, double y) { return Begin(x, y, Mode::relative); }
  bool BeginAbsolute(double x, double y, double pointer_x, double pointer_y) {
    if (!std::isfinite(pointer_x) || !std::isfinite(pointer_y)) {
      End();
      return false;
    }
    if (!Begin(x, y, Mode::absolute)) return false;
    pointer_x_ = pointer_x;
    pointer_y_ = pointer_y;
    return true;
  }
  bool AddRelative(double dx, double dy) {
    if (mode_ != Mode::relative) return false;
    return SetDelta(dx_ + dx, dy_ + dy);
  }
  bool SampleAbsolute(double x, double y) {
    if (mode_ != Mode::absolute) return false;
    return SetDelta(x - pointer_x_, y - pointer_y_);
  }
  bool Position(double* x, double* y) const {
    if (mode_ == Mode::none || !x || !y) return false;
    *x = x_ + dx_;
    *y = y_ + dy_;
    return true;
  }
  void End() { mode_ = Mode::none; x_ = y_ = dx_ = dy_ = pointer_x_ = pointer_y_ = 0; }

 private:
  enum class Mode { none, relative, absolute };
  bool Begin(double x, double y, Mode mode) {
    End();
    if (!std::isfinite(x) || !std::isfinite(y)) return false;
    x_ = x;
    y_ = y;
    mode_ = mode;
    return true;
  }
  bool SetDelta(double x, double y) {
    if (!std::isfinite(x) || !std::isfinite(y) ||
        !std::isfinite(x_ + x) || !std::isfinite(y_ + y)) return false;
    dx_ = x;
    dy_ = y;
    return true;
  }
  Mode mode_ = Mode::none;
  double x_ = 0, y_ = 0, dx_ = 0, dy_ = 0, pointer_x_ = 0, pointer_y_ = 0;
};
}  // namespace mvd
#endif  // MVD_LINUX_POMO_DRAG_STATE_H_
