#ifndef MVD_LINUX_COLOR_H_
#define MVD_LINUX_COLOR_H_
namespace mvd {
struct BackgroundColor {
  int red, green, blue, alpha;
};
// Read the wire contract shared by createWindow and setBackgroundColor.
template <class Read>
BackgroundColor DecodeBackgroundColor(Read read) {
  return {static_cast<int>(read("backgroundColorR", 0)),
          static_cast<int>(read("backgroundColorG", 0)),
          static_cast<int>(read("backgroundColorB", 0)),
          static_cast<int>(read("backgroundColorA", 255))};
}
}  // namespace mvd
#endif
