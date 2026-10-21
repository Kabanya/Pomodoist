#ifndef MVD_LINUX_LOG_H_
#define MVD_LINUX_LOG_H_

#include <glib.h>

// Uncomment to enable native MVD debug logging:
// #define MVD_ENABLE_LOG

#ifdef MVD_ENABLE_LOG
#define MVD_LOG_TAG(tag, fmt, ...)                                     \
  g_print("[MVD %.6f] [" tag "] " fmt "\n",                           \
          static_cast<double>(g_get_monotonic_time()) / 1e6,           \
          ##__VA_ARGS__)
#else
// Keep arguments type-checked and marked used when logging is disabled.
#define MVD_LOG_TAG(tag, fmt, ...)                                     \
  do {                                                                 \
    if (0) {                                                           \
      g_print("[MVD] [" tag "] " fmt "\n", ##__VA_ARGS__);             \
    }                                                                  \
  } while (0)
#endif

#define MVD_LOG_WINDOW(fmt, ...) MVD_LOG_TAG("window", fmt, ##__VA_ARGS__)
#define MVD_LOG_PLUGIN(fmt, ...) MVD_LOG_TAG("plugin", fmt, ##__VA_ARGS__)
#define MVD_LOG_RUNNER(fmt, ...) MVD_LOG_TAG("runner", fmt, ##__VA_ARGS__)

#endif  // MVD_LINUX_LOG_H_
