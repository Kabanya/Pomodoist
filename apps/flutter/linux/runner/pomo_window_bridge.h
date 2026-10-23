#ifndef RUNNER_POMO_WINDOW_BRIDGE_H_
#define RUNNER_POMO_WINDOW_BRIDGE_H_
#include <flutter_linux/flutter_linux.h>
#include <multiview_desktop/multiview_desktop_runner.h>

inline FlMethodChannel* CreatePomoWindowChannel(FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "pomodoist/pomo_window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel,
      [](FlMethodChannel*, FlMethodCall* call, gpointer) {
        multiview_desktop_linux_pomo_call(call);
      }, nullptr, nullptr);
  return channel;
}
#endif  // RUNNER_POMO_WINDOW_BRIDGE_H_
