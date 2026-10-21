#ifndef MULTI_VIEW_DESKTOP_PLUGIN_MULTI_VIEW_DESKTOP_H_
#define MULTI_VIEW_DESKTOP_PLUGIN_MULTI_VIEW_DESKTOP_H_

#include <shobjidl_core.h>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

#include <codecvt>
#include <dwmapi.h>
#include <map>
#include <memory>
#include <sstream>
#include <string>

#define STATE_NORMAL 0
#define STATE_MAXIMIZED 1
#define STATE_MINIMIZED 2
#define STATE_FULLSCREEN_ENTERED 3

// Internal multi-view API (not yet in the public Flutter Windows SDK).
typedef struct {
  int width;
  int height;
} FlutterDesktopViewControllerProperties;

extern "C" FlutterDesktopViewControllerRef
FlutterDesktopEngineCreateViewController(
    FlutterDesktopEngineRef engine,
    const FlutterDesktopViewControllerProperties* properties);

namespace multi_view_desktop {

class MultiViewDesktop {
 public:
  MultiViewDesktop();

  virtual ~MultiViewDesktop();

  static MultiViewDesktop& Instance();

  void SetEngine(FlutterDesktopEngineRef engine);
  FlutterDesktopEngineRef engine() const { return engine_; }

  void SetMainHostWindow(HWND hwnd) { main_host_window_ = hwnd; }
  int64_t main_view_id() const { return main_view_id_; }

  void SetupChannel(flutter::BinaryMessenger* messenger);
  flutter::MethodChannel<flutter::EncodableValue>* channel() {
    return channel_.get();
  }
  void RegisterMain(HWND window,
                    int64_t view_id,
                    FlutterDesktopViewControllerRef controller);
  void RegisterWindow(HWND window,
                      int64_t view_id,
                      FlutterDesktopViewControllerRef controller);

  MultiViewDesktop* FindByViewId(int64_t view_id);
  MultiViewDesktop* FindByHwnd(HWND hwnd);
  int64_t ViewIdForHwnd(HWND hwnd) const;
  void DestroyEntry(int64_t view_id);

  void CreateSecondaryWindow(const flutter::EncodableMap& args);
  void CreateModalDialogWindow(const flutter::EncodableMap& args);

  void EmitEvent(const std::string& event_name, int64_t view_id);
  void EmitTaskbarMenuItemSelected(int menu_item_id);

  static void UpdateModalStateLayer(HWND owner_hwnd);

  static void ResizeFlutterContent(MultiViewDesktop* window);
  static HWND CreateHostTopLevelWindow(const std::wstring& title,
                                       int client_width,
                                       int client_height);
  static HWND CreateDialogHostWindow(const std::wstring& title,
                                     int client_width,
                                     int client_height,
                                     bool is_modal,
                                     bool show_close_button,
                                     HWND owner_hwnd);
  static void CenterDialogOnOwner(HWND dialog_hwnd, HWND owner_hwnd);
  static LRESULT CALLBACK HostWndProc(HWND hwnd,
                                      UINT message,
                                      WPARAM wparam,
                                      LPARAM lparam);

  int64_t view_id = -1;
  FlutterDesktopViewControllerRef controller = nullptr;
  HWND native_window = nullptr;
  int last_state = STATE_NORMAL;
  bool has_shadow_ = false;
  bool is_frameless_ = false;
  bool is_prevent_close_ = false;
  bool is_confirm_close_ = false;
  bool is_pre_confirm_ = false;
  double aspect_ratio_ = 0;
  POINT minimum_size_ = {0, 0};
  POINT maximum_size_ = {-1, -1};
  double pixel_ratio_ = 1;
  bool is_resizable_ = true;
  bool is_skip_taskbar_ = false;
  bool is_dialog_ = false;
  bool is_modal_ = false;
  int64_t modal_owner_view_id_ = -1;
  std::string title_bar_style_ = "normal";
  bool window_button_visibility_ = true;
  double opacity_ = 1;

  bool is_resizing_ = false;
  bool is_moving_ = false;

  HWND GetMainWindow();
  void ForceRefresh();
  void ForceChildRefresh();
  void SetAsFrameless();
  void Close();
  void SetConfirmClose(const flutter::EncodableMap& args);
  bool IsConfirmClose();
  bool IsPreventClose();
  void SetPreventClose(const flutter::EncodableMap& args);
  void SetPreConfirmClose(const flutter::EncodableMap& args);
  void Focus();
  void Blur();
  bool IsFocused();
  void Show();
  void Hide();
  bool IsVisible();
  bool IsMaximized();
  void Maximize(const flutter::EncodableMap& args);
  void Unmaximize();
  bool IsMinimized();
  void Minimize();
  void Restore();
  bool IsFullScreen();
  void SetFullScreen(const flutter::EncodableMap& args);
  void SetAspectRatio(const flutter::EncodableMap& args);
  void SetBackgroundColor(const flutter::EncodableMap& args);
  flutter::EncodableMap GetBounds(const flutter::EncodableMap& args);
  void SetSize(const flutter::EncodableMap& args);
  void SetPosition(const flutter::EncodableMap& args);
  void Center();
  void SetMinimumSize(const flutter::EncodableMap& args);
  void SetMaximumSize(const flutter::EncodableMap& args);
  bool IsResizable();
  void SetResizable(const flutter::EncodableMap& args);
  bool IsMinimizable();
  void SetMinimizable(const flutter::EncodableMap& args);
  bool IsMaximizable();
  void SetMaximizable(const flutter::EncodableMap& args);
  bool IsClosable();
  void SetClosable(const flutter::EncodableMap& args);
  bool IsAlwaysOnTop();
  void SetAlwaysOnTop(const flutter::EncodableMap& args);
  std::string GetTitle();
  void SetTitle(const flutter::EncodableMap& args);
  void SetTitleBarStyle(const flutter::EncodableMap& args);
  flutter::EncodableMap GetTitleBarStyle();
  bool IsMovable();
  void SetMovable(const flutter::EncodableMap& args);
  bool HasShadow();
  void SetHasShadow(const flutter::EncodableMap& args);
  void MultiViewDesktop::SetProgressBar(double progress);
  double GetOpacity();
  void SetOpacity(const flutter::EncodableMap& args);
  void SetBrightness(const flutter::EncodableMap& args);
  void SetIgnoreMouseEvents(const flutter::EncodableMap& args);
  flutter::EncodableMap IsIgnoreMouseEvents();
  void PopUpWindowMenu(const flutter::EncodableMap& args);
  void StartDragging();
  void StartResizing(const flutter::EncodableMap& args);

  bool IsSkipTaskbar();
  void SetSkipTaskbar(const flutter::EncodableMap& args);

  static int64_t Int64FromMap(const flutter::EncodableMap& args, const char* key);
  static double DoubleFromMap(const flutter::EncodableMap& args,
                              const char* key,
                              double fallback);
  static bool BoolFromMap(const flutter::EncodableMap& args,
                          const char* key,
                          bool fallback);

  static FlutterDesktopEngineRef engine_;
  static HWND main_host_window_;
  static int64_t main_view_id_;
  static bool terminate_after_last_window_closed_;
  static std::map<int64_t, std::unique_ptr<MultiViewDesktop>> windows_;
  static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

 private:
  bool focus_on_show_ = true;
  static std::string StringFromMap(const flutter::EncodableMap& args,
                                   const char* key,
                                   const std::string& fallback = {});

  bool g_is_window_fullscreen = false;
  std::string g_title_bar_style_before_fullscreen;
  RECT g_frame_before_fullscreen{};
  bool g_maximized_before_fullscreen = false;
  LONG g_style_before_fullscreen = 0;
  double GetDpiForHwnd(HWND hWnd);
};

}  // namespace multi_view_desktop

#endif  // MULTI_VIEW_DESKTOP_PLUGIN_MULTI_VIEW_DESKTOP_H_
