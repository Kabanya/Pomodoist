#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter_windows.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject &project);
  virtual ~FlutterWindow();

protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

private:
  void ConfigureQuickAddChannel(FlutterDesktopEngineRef engine);
  void ConfigureNativeLinkChannel(FlutterDesktopEngineRef engine);
  bool SetQuickAddEnabled(bool enabled);

  // The project to run.
  flutter::DartProject project_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      quick_add_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      native_link_channel_;
  bool quick_add_enabled_ = false;
  UINT quick_add_modifiers_ = MOD_CONTROL | MOD_ALT;
  UINT quick_add_virtual_key_ = VK_SPACE;
  std::string quick_add_key_label_ = "Space";
};

#endif // RUNNER_FLUTTER_WINDOW_H_
