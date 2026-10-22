#include "../mvd_linux_color.h"
#include <cassert>
#include <map>
#include <string>

int main() {
  // Literal Dart NativeChannel.setBackgroundColor / createWindow payload.
  const std::map<std::string, double> payload{
      {"backgroundColorR", 12}, {"backgroundColorG", 34},
      {"backgroundColorB", 56}, {"backgroundColorA", 0}};
  const auto decoded = mvd::DecodeBackgroundColor([&](const char* key, double fallback) {
    const auto value = payload.find(key);
    return value == payload.end() ? fallback : value->second;
  });
  assert(decoded.alpha == 0);
  assert(decoded.red == 12 && decoded.green == 34 && decoded.blue == 56);
  const auto defaults = mvd::DecodeBackgroundColor([](const char*, double fallback) { return fallback; });
  assert(defaults.alpha == 255);
  assert(defaults.red == 0 && defaults.green == 0 && defaults.blue == 0);
}
