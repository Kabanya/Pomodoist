#ifndef RUNNER_APP_ICON_HOST_H_
#define RUNNER_APP_ICON_HOST_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <memory>
#include <string>

#include "flavor_config.h"

namespace app_icon {

struct State;

inline State *&ActiveState() {
  static State *state = nullptr;
  return state;
}

struct State {
  std::string selected = "icon-light-pomo";
  HICON large = nullptr;
  HICON small = nullptr;
  HHOOK window_hook = nullptr;
  ~State() {
    if (window_hook)
      UnhookWindowsHookEx(window_hook);
    if (ActiveState() == this)
      ActiveState() = nullptr;
    if (large)
      DestroyIcon(large);
    if (small)
      DestroyIcon(small);
  }
};

inline HRESULT UpdateShortcut(const std::wstring &executable,
                              const std::wstring &icon) {
  PWSTR programs = nullptr;
  HRESULT status =
      SHGetKnownFolderPath(FOLDERID_Programs, 0, nullptr, &programs);
  if (FAILED(status))
    return status;
  const std::wstring path = std::wstring(programs) + L"\\" +
                            POMODOIST_FLAVOR_DISPLAY_NAME_WIDE + L".lnk";
  CoTaskMemFree(programs);
  if (GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) {
    const DWORD error = GetLastError();
    return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND
               ? S_OK
               : HRESULT_FROM_WIN32(error);
  }
  Microsoft::WRL::ComPtr<IShellLinkW> link;
  status = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                            IID_PPV_ARGS(link.GetAddressOf()));
  if (FAILED(status))
    return status;
  Microsoft::WRL::ComPtr<IPersistFile> file;
  status = link.As(&file);
  if (FAILED(status))
    return status;
  status = file->Load(path.c_str(), STGM_READWRITE);
  if (FAILED(status))
    return status;
  wchar_t target[32768] = {};
  status = link->GetPath(target, 32768, nullptr, SLGP_RAWPATH);
  if (FAILED(status))
    return status;
  // Only the current installation's own Start menu shortcut is managed here.
  if (_wcsicmp(target, executable.c_str()) != 0)
    return S_OK;
  status = link->SetIconLocation(icon.c_str(), 0);
  if (FAILED(status))
    return status;
  GUID nonce;
  status = CoCreateGuid(&nonce);
  if (FAILED(status))
    return status;
  wchar_t suffix[40] = {};
  StringFromGUID2(nonce, suffix, 40);
  const std::wstring temporary = path + suffix + L".tmp";
  status = file->Save(temporary.c_str(), FALSE);
  if (SUCCEEDED(status) &&
      !MoveFileExW(temporary.c_str(), path.c_str(),
                   MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
    status = HRESULT_FROM_WIN32(GetLastError());
  DeleteFileW(temporary.c_str());
  if (FAILED(status))
    return status;
  SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW, path.c_str(), nullptr);
  return S_OK;
}

inline BOOL CALLBACK ApplyToWindow(HWND window, LPARAM parameter) {
  if (reinterpret_cast<HINSTANCE>(GetClassLongPtrW(window, GCLP_HMODULE)) !=
      GetModuleHandleW(nullptr))
    return TRUE;
  auto *state = reinterpret_cast<State *>(parameter);
  SendMessageW(window, WM_SETICON, ICON_BIG,
               reinterpret_cast<LPARAM>(state->large));
  SendMessageW(window, WM_SETICON, ICON_SMALL,
               reinterpret_cast<LPARAM>(state->small));
  // Keep both the window and its class consistent with the selected icon.
  SetClassLongPtrW(window, GCLP_HICON,
                   reinterpret_cast<LONG_PTR>(state->large));
  SetClassLongPtrW(window, GCLP_HICONSM,
                   reinterpret_cast<LONG_PTR>(state->small));
  return TRUE;
}

inline LRESULT CALLBACK WindowHook(int code, WPARAM parameter, LPARAM details) {
  auto *state = ActiveState();
  // The multiview class is registered lazily, after preference restoration.
  if (state && state->large &&
      (code == HCBT_CREATEWND || code == HCBT_ACTIVATE)) {
    ApplyToWindow(reinterpret_cast<HWND>(parameter),
                  reinterpret_cast<LPARAM>(state));
  }
  return CallNextHookEx(nullptr, code, parameter, details);
}

inline std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateChannel(FlutterDesktopEngineRef engine) {
  auto *registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(
              FlutterDesktopEngineGetPluginRegistrar(engine, "AppIconHost"));
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "pomodoist/app_icon",
          &flutter::StandardMethodCodec::GetInstance());
  auto state = std::make_shared<State>();
  state->window_hook =
      SetWindowsHookExW(WH_CBT, WindowHook, nullptr, GetCurrentThreadId());
  ActiveState() = state.get();
  channel->SetMethodCallHandler([state](const auto &call, auto result) {
    if (call.method_name() == "getIcon") {
      result->Success(flutter::EncodableValue(state->selected));
      return;
    }
    if (call.method_name() != "setIcon") {
      result->NotImplemented();
      return;
    }
    const auto *args = std::get_if<flutter::EncodableMap>(call.arguments());
    const std::string *icon = nullptr;
    if (args) {
      const auto found = args->find(flutter::EncodableValue("icon"));
      if (found != args->end())
        icon = std::get_if<std::string>(&found->second);
    }
    if (!icon || (*icon != "classic" && *icon != "icon-light-pomo")) {
      result->Error("invalid_icon", "Unsupported app icon.");
      return;
    }
    if (!state->window_hook) {
      result->Error("icon_failed", "Could not monitor application windows.");
      return;
    }
    wchar_t executable_buffer[32768] = {};
    const DWORD length = GetModuleFileNameW(nullptr, executable_buffer, 32768);
    if (length == 0 || length >= 32768) {
      result->Error("icon_failed", "Could not resolve the application path.");
      return;
    }
    const std::wstring executable(executable_buffer, length);
    const std::wstring base =
        executable.substr(0, executable.find_last_of(L"\\/"));
    const std::string asset =
        std::string(POMODOIST_FLAVOR_NAME) + "/" + *icon + ".ico";
    const std::wstring path =
        base +
        L"\\data\\flutter_assets\\assets\\branding\\app_icons\\generated\\" +
        std::wstring(asset.begin(), asset.end());
    HICON large = static_cast<HICON>(LoadImageW(
        nullptr, path.c_str(), IMAGE_ICON, GetSystemMetrics(SM_CXICON),
        GetSystemMetrics(SM_CYICON), LR_LOADFROMFILE));
    HICON small = static_cast<HICON>(LoadImageW(
        nullptr, path.c_str(), IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
        GetSystemMetrics(SM_CYSMICON), LR_LOADFROMFILE));
    if (!large || !small || FAILED(UpdateShortcut(executable, path))) {
      if (large)
        DestroyIcon(large);
      if (small)
        DestroyIcon(small);
      result->Error("icon_failed",
                    "Could not load the app icon or update its shortcut.");
      return;
    }
    HICON previous_large = state->large;
    HICON previous_small = state->small;
    state->large = large;
    state->small = small;
    EnumThreadWindows(GetCurrentThreadId(), ApplyToWindow,
                      reinterpret_cast<LPARAM>(state.get()));
    state->selected = *icon;
    if (previous_large)
      DestroyIcon(previous_large);
    if (previous_small)
      DestroyIcon(previous_small);
    result->Success();
  });
  return channel;
}

} // namespace app_icon
#endif
