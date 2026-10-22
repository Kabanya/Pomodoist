#ifndef MVD_LINUX_POMO_GEOMETRY_H_
#define MVD_LINUX_POMO_GEOMETRY_H_

#include <algorithm>
#include <cmath>
#include <vector>

namespace mvd {
struct LayerMargins { int left; int top; };
inline LayerMargins LayerPlacement(int work_x, int work_y, double x, double y) {
  return {static_cast<int>(std::round(x - work_x)),
          static_cast<int>(std::round(y - work_y))};
}
struct InputShape {
  double x, y, width, height;
  bool rectangle, rounded;
};
struct InputRectangle { int x, y, width, height; };
// GDK input regions use logical integer coordinates. Scan the curved shapes at
// pixel centers so transparent corners pass through without clipping the view.
inline std::vector<InputRectangle> InputRectangles(const InputShape& shape) {
  std::vector<InputRectangle> result;
  if (!std::isfinite(shape.x) || !std::isfinite(shape.y) ||
      !std::isfinite(shape.width) || !std::isfinite(shape.height) ||
      shape.width <= 0 || shape.height <= 0) return result;
  const int top = static_cast<int>(std::floor(shape.y));
  const int bottom = static_cast<int>(std::ceil(shape.y + shape.height));
  if (shape.rectangle) {
    const int left = static_cast<int>(std::floor(shape.x));
    result.push_back({left, top,
        static_cast<int>(std::ceil(shape.x + shape.width)) - left, bottom - top});
    return result;
  }
  const double ry = shape.height / 2;
  const double rx = shape.rounded ? std::min(shape.width / 2, ry) : shape.width / 2;
  for (int y = top; y < bottom; ++y) {
    const double dy = (y + 0.5 - shape.y - ry) / ry;
    const double inset = rx * (1 - std::sqrt(std::max(0.0, 1 - dy * dy)));
    const int left = static_cast<int>(std::ceil(shape.x + inset - 0.5));
    const int right = static_cast<int>(std::ceil(shape.x + shape.width - inset - 0.5));
    if (right > left) result.push_back({left, y, right - left, 1});
  }
  return result;
}
}  // namespace mvd
#endif  // MVD_LINUX_POMO_GEOMETRY_H_
