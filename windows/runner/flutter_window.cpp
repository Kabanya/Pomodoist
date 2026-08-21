#include "flutter_window.h"

#include <cctype>

#include <app_links/app_links_plugin_c_api.h>
#include <audioplayers_windows/audioplayers_windows_plugin.h>
#include <file_selector_windows/file_selector_windows.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter_secure_storage_windows/flutter_secure_storage_windows_plugin.h>
#include <flutter_timezone/flutter_timezone_plugin_c_api.h>
#include <multiview_desktop/multi_view_desktop_plugin.h>
#include <record_windows/record_windows_plugin_c_api.h>
#include <sentry_flutter/sentry_flutter_plugin.h>
#include <url_launcher_windows/url_launcher_windows.h>

namespace {

constexpr int kQuickAddHotKeyId = 1;
constexpr char kQuickAddChannel[] = "pomodoist/quick_add";

const flutter::EncodableValue *FindValue(const flutter::EncodableMap &map,
                                         const char *key) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  return iterator == map.end() ? nullptr : &iterator->second;
}

bool ReadBool(const flutter::EncodableMap &map, const char *key, bool *value) {
  const auto *encoded = FindValue(map, key);
  const auto *boolean =
      encoded == nullptr ? nullptr : std::get_if<bool>(encoded);
  if (boolean == nullptr) {
    return false;
  }
  *value = *boolean;
  return true;
}

UINT VirtualKeyForLabel(const std::string &label, int fallback) {
  if (label == "Space")
    return VK_SPACE;
  if (label == "Enter")
    return VK_RETURN;
  if (label == "Tab")
    return VK_TAB;
  if (label == "Delete")
    return VK_DELETE;
  if (label == "Backspace")
    return VK_BACK;
  if (label == "Escape" || label == "Esc")
    return VK_ESCAPE;
  if (label == "Home")
    return VK_HOME;
  if (label == "End")
    return VK_END;
  if (label == "Page Up")
    return VK_PRIOR;
  if (label == "Page Down")
    return VK_NEXT;
  if (label == "Arrow Left" || label == "←")
    return VK_LEFT;
  if (label == "Arrow Right" || label == "→")
    return VK_RIGHT;
  if (label == "Arrow Up" || label == "↑")
    return VK_UP;
  if (label == "Arrow Down" || label == "↓")
    return VK_DOWN;
  if (label.size() == 1) {
    const auto character = static_cast<wchar_t>(
        std::toupper(static_cast<unsigned char>(label.front())));
    const SHORT mapped = VkKeyScanW(character);
    if (mapped != -1)
      return LOBYTE(mapped);
  }
  return fallback > 0 && fallback < 0xFF ? static_cast<UINT>(fallback) : 0;
}

void RegisterPomodoistPlugins(FlutterDesktopEngineRef engine) {
  AppLinksPluginCApiRegisterWithRegistrar(
      FlutterDesktopEngineGetPluginRegistrar(engine, "AppLinksPluginCApi"));
  AudioplayersWindowsPluginRegisterWithRegistrar(
      FlutterDesktopEngineGetPluginRegistrar(engine,
                                             "AudioplayersWindowsPlugin"));
  FileSelectorWindowsRegisterWithRegistrar(
      FlutterDesktopEngineGetPluginRegistrar(engine, "FileSelectorWindows"));
  FlutterSecureStorageWindowsPluginRegisterWithRegistrar(
      FlutterDesktopEngineGetPluginRegistrar(
          engine, "FlutterSecureStorageWindowsPlugin"));
  FlutterTimezonePluginCApiRegisterWithRegistrar(
      FlutterDesktopEngineGetPluginRegistrar(engine,
                                             "FlutterTimezonePluginCApi"));
  RecordWindowsPluginCApiRegisterWithRegistrar(
      FlutterDesktopEngineGetPluginRegistrar(engine,
                                             "RecordWindowsPluginCApi"));
  SentryFlutterPluginRegisterWithRegistrar(
      FlutterDesktopEngineGetPluginRegistrar(engine, "SentryFlutterPlugin"));
  UrlLauncherWindowsRegisterWithRegistrar(
      FlutterDesktopEngineGetPluginRegistrar(engine, "UrlLauncherWindows"));
}

} // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject &project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  const int width = frame.right - frame.left;
  const int height = frame.bottom - frame.top;
  MultiViewDesktopPrepareEngine(project_, GetHandle());
  MultiViewDesktopCreateMainView(GetHandle(), width, height);
  FlutterDesktopEngineRef engine = MultiViewDesktopGetEngineRef();
  if (engine == nullptr) {
    return false;
  }
  RegisterPomodoistPlugins(engine);
  ConfigureQuickAddChannel(engine);
  const HWND flutter_hwnd =
      MultiViewDesktopGetFlutterHwnd(MultiViewDesktopGetMainViewId());
  if (flutter_hwnd != nullptr) {
    SetChildContent(flutter_hwnd);
  }

  return true;
}

void FlutterWindow::OnDestroy() {
  if (quick_add_enabled_) {
    UnregisterHotKey(GetHandle(), kQuickAddHotKeyId);
  }
  quick_add_channel_.reset();
  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  LRESULT result = 0;
  if (message == WM_HOTKEY && wparam == kQuickAddHotKeyId &&
      quick_add_channel_) {
    quick_add_channel_->InvokeMethod(
        "showQuickAdd", std::make_unique<flutter::EncodableValue>());
    return 0;
  }
  if (message == WM_FONTCHANGE) {
    FlutterDesktopEngineReloadSystemFonts(MultiViewDesktopGetEngineRef());
  }
  if (MultiViewDesktopHandleWindowProc(hwnd, message, wparam, lparam,
                                       &result)) {
    return result;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::ConfigureQuickAddChannel(FlutterDesktopEngineRef engine) {
  auto registrar = flutter::PluginRegistrarManager::GetInstance()
                       ->GetRegistrar<flutter::PluginRegistrarWindows>(
                           FlutterDesktopEngineGetPluginRegistrar(
                               engine, "PomodoistQuickAddHost"));
  quick_add_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), kQuickAddChannel,
          &flutter::StandardMethodCodec::GetInstance());
  quick_add_channel_->SetMethodCallHandler([this](const auto &call,
                                                  auto result) {
    if (call.method_name() == "getGlobalShortcut") {
      flutter::EncodableMap value{
          {flutter::EncodableValue("keyCode"),
           flutter::EncodableValue(
               static_cast<int32_t>(quick_add_virtual_key_))},
          {flutter::EncodableValue("keyLabel"),
           flutter::EncodableValue(quick_add_key_label_)},
          {flutter::EncodableValue("meta"),
           flutter::EncodableValue((quick_add_modifiers_ & MOD_WIN) != 0)},
          {flutter::EncodableValue("control"),
           flutter::EncodableValue((quick_add_modifiers_ & MOD_CONTROL) != 0)},
          {flutter::EncodableValue("alt"),
           flutter::EncodableValue((quick_add_modifiers_ & MOD_ALT) != 0)},
          {flutter::EncodableValue("shift"),
           flutter::EncodableValue((quick_add_modifiers_ & MOD_SHIFT) != 0)},
      };
      result->Success(flutter::EncodableValue(value));
      return;
    }
    if (call.method_name() == "setGlobalShortcutEnabled") {
      const auto *enabled = std::get_if<bool>(call.arguments());
      if (enabled == nullptr) {
        result->Error("invalid_arguments", "Expected a boolean value.");
      } else if (!SetQuickAddEnabled(*enabled)) {
        result->Error("shortcut_unavailable",
                      "The global keyboard shortcut is unavailable.");
      } else {
        result->Success();
      }
      return;
    }
    if (call.method_name() == "setGlobalShortcut") {
      const auto *arguments =
          std::get_if<flutter::EncodableMap>(call.arguments());
      const auto *key_code_value =
          arguments == nullptr ? nullptr : FindValue(*arguments, "keyCode");
      const auto *key_label_value =
          arguments == nullptr ? nullptr : FindValue(*arguments, "keyLabel");
      const auto *key_code = key_code_value == nullptr
                                 ? nullptr
                                 : std::get_if<int32_t>(key_code_value);
      const auto *key_label = key_label_value == nullptr
                                  ? nullptr
                                  : std::get_if<std::string>(key_label_value);
      bool meta = false;
      bool control = false;
      bool alt = false;
      bool shift = false;
      if (arguments == nullptr || key_code == nullptr || key_label == nullptr ||
          !ReadBool(*arguments, "meta", &meta) ||
          !ReadBool(*arguments, "control", &control) ||
          !ReadBool(*arguments, "alt", &alt) ||
          !ReadBool(*arguments, "shift", &shift)) {
        result->Error("invalid_shortcut", "The keyboard shortcut is invalid.");
        return;
      }
      const UINT virtual_key = VirtualKeyForLabel(*key_label, *key_code);
      const UINT modifiers = (meta ? MOD_WIN : 0) |
                             (control ? MOD_CONTROL : 0) | (alt ? MOD_ALT : 0) |
                             (shift ? MOD_SHIFT : 0);
      if (virtual_key == 0 ||
          (modifiers & (MOD_WIN | MOD_CONTROL | MOD_ALT)) == 0) {
        result->Error("invalid_shortcut", "The keyboard shortcut is invalid.");
        return;
      }

      const UINT previous_key = quick_add_virtual_key_;
      const UINT previous_modifiers = quick_add_modifiers_;
      if (quick_add_enabled_) {
        UnregisterHotKey(GetHandle(), kQuickAddHotKeyId);
        if (!RegisterHotKey(GetHandle(), kQuickAddHotKeyId,
                            modifiers | MOD_NOREPEAT, virtual_key)) {
          RegisterHotKey(GetHandle(), kQuickAddHotKeyId,
                         previous_modifiers | MOD_NOREPEAT, previous_key);
          result->Error("shortcut_unavailable",
                        "The global keyboard shortcut is unavailable.");
          return;
        }
      }
      quick_add_virtual_key_ = virtual_key;
      quick_add_modifiers_ = modifiers;
      quick_add_key_label_ = *key_label;
      result->Success();
      return;
    }
    result->NotImplemented();
  });
}

bool FlutterWindow::SetQuickAddEnabled(bool enabled) {
  if (enabled == quick_add_enabled_)
    return true;
  if (!enabled) {
    if (!UnregisterHotKey(GetHandle(), kQuickAddHotKeyId)) {
      return false;
    }
    quick_add_enabled_ = false;
    return true;
  }
  if (!RegisterHotKey(GetHandle(), kQuickAddHotKeyId,
                      quick_add_modifiers_ | MOD_NOREPEAT,
                      quick_add_virtual_key_)) {
    return false;
  }
  quick_add_enabled_ = true;
  return true;
}
