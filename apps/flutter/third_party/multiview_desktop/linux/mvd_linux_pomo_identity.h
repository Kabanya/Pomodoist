#ifndef MVD_LINUX_POMO_IDENTITY_H_
#define MVD_LINUX_POMO_IDENTITY_H_

#include <set>
#include <string>

namespace mvd {
// Call only for a monitor without a cached ID. The caller supplies IDs cached
// on other currently connected monitors, so unplugged objects cannot reserve
// identifiers forever. Existing connected monitors retain their cached IDs.
inline std::string AvailableMonitorId(const std::string& base,
                                     const std::set<std::string>& connected_ids) {
  std::string id = base;
  unsigned ordinal = 1;
  while (connected_ids.count(id)) id = base + ":" + std::to_string(++ordinal);
  return id;
}
}  // namespace mvd
#endif  // MVD_LINUX_POMO_IDENTITY_H_
