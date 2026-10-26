#ifndef RUNNER_DISTRACTION_PROTECTION_H_
#define RUNNER_DISTRACTION_PROTECTION_H_
#include <algorithm>
#include <appmodel.h>
#include <cstdio>
#include <cwctype>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <gdiplus.h>
#include <memory>
#include <set>
#include <shlwapi.h>
#include <string>
#include <vector>
#include <windows.h>

namespace distractions {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
inline const Value *Field(const Map &map, const char *key) {
  auto found = map.find(Value(key));
  return found == map.end() ? nullptr : &found->second;
}
inline std::string Utf8(const std::wstring &text) {
  if (text.empty())
    return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, text.data(),
                              static_cast<int>(text.size()), nullptr, 0,
                              nullptr, nullptr);
  std::string value(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      value.data(), n, nullptr, nullptr);
  return value;
}
inline std::wstring Wide(const std::string &text) {
  int n = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                              static_cast<int>(text.size()), nullptr, 0);
  std::wstring value(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      value.data(), n);
  return value;
}
inline ULONGLONG Now() {
  FILETIME time;
  GetSystemTimeAsFileTime(&time);
  ULARGE_INTEGER n;
  n.LowPart = time.dwLowDateTime;
  n.HighPart = time.dwHighDateTime;
  return n.QuadPart;
}
inline ULONGLONG Deadline(const std::string &iso) {
  unsigned y, m, d, h, n, s;
  if (iso.size() < 20 || iso.back() != 'Z' ||
      sscanf_s(iso.c_str(), "%u-%u-%uT%u:%u:%u", &y, &m, &d, &h, &n, &s) != 6)
    return 0;
  SYSTEMTIME time{};
  time.wYear = static_cast<WORD>(y);
  time.wMonth = static_cast<WORD>(m);
  time.wDay = static_cast<WORD>(d);
  time.wHour = static_cast<WORD>(h);
  time.wMinute = static_cast<WORD>(n);
  time.wSecond = static_cast<WORD>(s);
  FILETIME file;
  if (!SystemTimeToFileTime(&time, &file))
    return 0;
  ULARGE_INTEGER result;
  result.LowPart = file.dwLowDateTime;
  result.HighPart = file.dwHighDateTime;
  return result.QuadPart;
}
struct Host;
inline Host *&Current() {
  static Host *value = nullptr;
  return value;
}
struct Host {
  std::unique_ptr<flutter::MethodChannel<Value>> channel;
  HWND main = nullptr, shield = nullptr;
  HWINEVENTHOOK hook = nullptr;
  UINT_PTR timer = 0;
  bool discovery = false;
  bool countdown = true;
  ULONG_PTR graphics_token = 0;
  std::unique_ptr<Gdiplus::Image> mascot;
  IStream *mascot_stream = nullptr;
  bool quit_allowed = false;
  bool Protected() const { return !quit_allowed && expires > Now(); }
  ULONGLONG expires = 0, updated = 0;
  int seconds = 0;
  std::set<std::string> blocked;
  std::vector<std::pair<HWND, std::string>> minimized;
  std::string last, attempted;
  std::wstring task = L"Focus";
  ~Host() {
    mascot.reset();
    if (mascot_stream)
      mascot_stream->Release();
    if (graphics_token)
      Gdiplus::GdiplusShutdown(graphics_token);
    Clear();
    if (hook)
      UnhookWinEvent(hook);
    if (timer)
      KillTimer(nullptr, timer);
    if (shield)
      DestroyWindow(shield);
    if (Current() == this)
      Current() = nullptr;
  }
  std::pair<std::string, std::string> Identity(HWND window) {
    DWORD pid = 0;
    GetWindowThreadProcessId(window, &pid);
    if (!pid || pid == GetCurrentProcessId() || window == GetShellWindow() ||
        !IsWindowVisible(window))
      return {};
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process)
      return {};
    HANDLE token = nullptr;
    TOKEN_ELEVATION elevation{};
    DWORD size = 0;
    // Elevated and security windows are outside the adapter's authority.
    if (!OpenProcessToken(process, TOKEN_QUERY, &token)) {
      CloseHandle(process);
      return {};
    }
    bool elevated = !GetTokenInformation(token, TokenElevation, &elevation,
                                         sizeof(elevation), &size) ||
                    elevation.TokenIsElevated;
    CloseHandle(token);
    if (elevated) {
      CloseHandle(process);
      return {};
    }
    wchar_t path[32768];
    DWORD length = 32768;
    if (!QueryFullProcessImageNameW(process, 0, path, &length)) {
      CloseHandle(process);
      return {};
    }
    std::wstring name(path, length);
    auto slash = name.find_last_of(L"\\/");
    if (slash != std::wstring::npos)
      name.erase(0, slash + 1);
    std::transform(name.begin(), name.end(), name.begin(), [](wchar_t c) {
      return static_cast<wchar_t>(std::towlower(c));
    });
    if (name == L"explorer.exe" || name == L"shellexperiencehost.exe" ||
        name == L"startmenuexperiencehost.exe" || name == L"searchhost.exe" ||
        name == L"applicationframehost.exe" ||
        name == L"credentialuibroker.exe" ||
        name == L"securityhealthsystray.exe" || name == L"taskmgr.exe") {
      CloseHandle(process);
      return {};
    }
    UINT32 count = 0;
    std::string id;
    if (GetApplicationUserModelId(process, &count, nullptr) ==
            ERROR_INSUFFICIENT_BUFFER &&
        count < 512) {
      std::vector<wchar_t> app(count);
      if (GetApplicationUserModelId(process, &count, app.data()) ==
          ERROR_SUCCESS)
        id = "windows:aumid:" + Utf8(app.data());
    }
    CloseHandle(process);
    // Public Win32 executable basename is portable; the full binding stays
    // local.
    if (id.empty())
      id = "windows:win32:" + Utf8(name);
    return {id, Utf8(name)};
  }
  void Emit(const char *event, const std::pair<std::string, std::string> &app) {
    channel->InvokeMethod(event, std::make_unique<Value>(Map{
                                     {Value("id"), Value(app.first)},
                                     {Value("name"), Value(app.second)},
                                     {Value("platform"), Value("windows")}}));
  }
  void Clear() {
    expires = 0;
    blocked.clear();
    attempted.clear();
    if (shield)
      ShowWindow(shield, SW_HIDE);
    for (auto &item : minimized)
      if (IsWindow(item.first) && IsIconic(item.first) &&
          Identity(item.first).first == item.second)
        ShowWindow(item.first, SW_SHOWNOACTIVATE);
    minimized.clear();
  }
  static LRESULT CALLBACK ShieldProc(HWND window, UINT message, WPARAM w,
                                     LPARAM l) {
    auto *host = Current();
    if (message == WM_COMMAND && LOWORD(w) == 1 && host) {
      ShowWindow(window, SW_HIDE);
      ShowWindow(host->main, SW_RESTORE);
      SetForegroundWindow(host->main);
      return 0;
    }
    if (message == WM_CLOSE)
      return 0;
    if (message == WM_SETFOCUS) {
      SetFocus(GetDlgItem(window, 1));
      return 0;
    }
    if (message == WM_PAINT && host) {
      PAINTSTRUCT paint;
      HDC dc = BeginPaint(window, &paint);
      RECT rect;
      GetClientRect(window, &rect);
      FillRect(dc, &rect, GetSysColorBrush(COLOR_WINDOW));
      if (host->mascot) {
        Gdiplus::Graphics graphics(dc);
        graphics.DrawImage(host->mascot.get(), (rect.right - 180) / 2,
                           rect.bottom / 3 - 200, 180, 180);
      }
      EndPaint(window, &paint);
      return 0;
    }
    return DefWindowProcW(window, message, w, l);
  }
  void ShowShield() {
    if (!shield) {
      WNDCLASSW klass{};
      klass.lpfnWndProc = ShieldProc;
      klass.hInstance = GetModuleHandle(nullptr);
      klass.lpszClassName = L"PomodoistFocusProtection";
      klass.hCursor = LoadCursor(nullptr, IDC_ARROW);
      RegisterClassW(&klass);
      shield = CreateWindowExW(WS_EX_TOPMOST, klass.lpszClassName,
                               L"Focus protection", WS_POPUP, 0, 0, 0, 0,
                               nullptr, nullptr, klass.hInstance, nullptr);
      CreateWindowW(L"BUTTON", L"Return to task",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON, 0, 0,
                    180, 48, shield, reinterpret_cast<HMENU>(1),
                    klass.hInstance, nullptr);
      CreateWindowW(L"STATIC", L"", WS_CHILD | WS_VISIBLE | SS_CENTER, 0, 0, 0,
                    0, shield, reinterpret_cast<HMENU>(2), klass.hInstance,
                    nullptr);
      CreateWindowW(L"STATIC", L"", WS_CHILD | WS_VISIBLE | SS_CENTER, 0, 0, 0,
                    0, shield, reinterpret_cast<HMENU>(3), klass.hInstance,
                    nullptr);
      for (int id = 1; id <= 3; id++)
        SendMessageW(GetDlgItem(shield, id), WM_SETFONT,
                     reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)),
                     TRUE);
    }
    int x = GetSystemMetrics(SM_XVIRTUALSCREEN),
        y = GetSystemMetrics(SM_YVIRTUALSCREEN),
        width = GetSystemMetrics(SM_CXVIRTUALSCREEN),
        height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    MoveWindow(GetDlgItem(shield, 1), width / 2 - 90, height / 2 + 48, 180, 48,
               TRUE);
    MoveWindow(GetDlgItem(shield, 2), width / 8, height / 3, width * 3 / 4, 80,
               TRUE);
    MoveWindow(GetDlgItem(shield, 3), width / 8, height / 3 + 80, width * 3 / 4,
               48, TRUE);
    UpdateLabels();
    SetWindowPos(shield, HWND_TOPMOST, x, y, width, height, SWP_SHOWWINDOW);
    SetForegroundWindow(shield);
    // Windows may deny activation; never cover another app that still owns input.
    if (GetForegroundWindow() != shield) {
      ShowWindow(shield, SW_HIDE);
      return;
    }
    SetFocus(GetDlgItem(shield, 1));
    InvalidateRect(shield, nullptr, TRUE);
  }
  void UpdateLabels() {
    if (!shield)
      return;
    int remaining = std::max(
        0, seconds - (countdown ? static_cast<int>((Now() - updated) / 10000000)
                                : 0));
    std::wstring time = L"Remaining time: " + std::to_wstring(remaining / 60) +
                        L":" + (remaining % 60 < 10 ? L"0" : L"") +
                        std::to_wstring(remaining % 60);
    SetWindowTextW(GetDlgItem(shield, 2), task.c_str());
    SetWindowTextW(GetDlgItem(shield, 3), time.c_str());
  }
  void Inspect() {
    if (expires && Now() >= expires)
      Clear();
    if (!discovery && !expires)
      return;
    HWND foreground = GetForegroundWindow();
    if (foreground == shield) {
      UpdateLabels();
      if (shield)
        InvalidateRect(shield, nullptr, TRUE);
      return;
    }
    auto app = Identity(foreground);
    if (app.first.empty()) {
      if (shield)
        ShowWindow(shield, SW_HIDE);
      return;
    }
    if (discovery && last != app.first) {
      last = app.first;
      Emit("foregroundApp", app);
    }
    if (!expires || !blocked.count(app.first)) {
      attempted.clear();
      if (shield)
        ShowWindow(shield, SW_HIDE);
      return;
    }
    if (attempted != app.first) {
      attempted = app.first;
      Emit("blockedAttempt", app);
    }
    if (!IsIconic(foreground)) {
      minimized.emplace_back(foreground, app.first);
      ShowWindow(foreground, SW_MINIMIZE);
    }
    ShowShield();
  }
  static void CALLBACK Foreground(HWINEVENTHOOK, DWORD, HWND, LONG, LONG, DWORD,
                                  DWORD) {
    if (Current())
      Current()->Inspect();
  }
  static void CALLBACK Tick(HWND, UINT, UINT_PTR, DWORD) {
    if (Current())
      Current()->Inspect();
  }
  explicit Host(FlutterDesktopEngineRef engine, HWND window) : main(window) {
    Current() = this;
    Gdiplus::GdiplusStartupInput graphics_input;
    if (Gdiplus::GdiplusStartup(&graphics_token, &graphics_input, nullptr) !=
        Gdiplus::Ok)
      graphics_token = 0;
    flutter::BinaryMessenger *messenger =
        flutter::PluginRegistrarManager::GetInstance()
            ->GetRegistrar<flutter::PluginRegistrarWindows>(
                FlutterDesktopEngineGetPluginRegistrar(engine,
                                                       "PomodoistDistractions"))
            ->messenger();
    channel = std::make_unique<flutter::MethodChannel<Value>>(
        messenger, "pomodoist/distractions",
        &flutter::StandardMethodCodec::GetInstance());
    hook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
                           nullptr, Foreground, 0, 0, WINEVENT_OUTOFCONTEXT);
    timer = SetTimer(nullptr, 0, 500, Tick);
    channel->SetMethodCallHandler([this](const auto &call, auto result) {
      auto method = call.method_name();
      if (method == "capabilities") {
        result->Success(Value(Map{
            {Value("supported"), Value(hook != nullptr && timer != 0)},
            {Value("discoveryAvailable"), Value(hook != nullptr)},
            {Value("platform"), Value("windows")},
            {Value("adapter"), Value("win-event-minimize-shield")},
            {Value("reason"), Value(hook != nullptr && timer != 0
                                        ? ""
                                        : "Windows foreground event hook or "
                                          "expiry timer is unavailable.")}}));
        return;
      }
      if (method == "allowQuit") {
        quit_allowed = true;
        Clear();
        result->Success();
        PostQuitMessage(0);
        return;
      }
      if (method == "startDiscovery") {
        discovery = true;
        last.clear();
        Inspect();
        result->Success();
        return;
      }
      if (method == "stopDiscovery") {
        discovery = false;
        result->Success();
        return;
      }
      if (method == "clearProtection") {
        Clear();
        result->Success();
        return;
      }
      if (method != "setProtection") {
        result->NotImplemented();
        return;
      }
      const auto *args =
          call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      if (!args) {
        result->Error("invalid_protection", "Missing protection snapshot.");
        return;
      }
      const Value *active = Field(*args, "active");
      if (!active || !std::holds_alternative<bool>(*active)) {
        result->Error("invalid_protection", "Invalid protection state.");
        return;
      }
      if (!std::get<bool>(*active)) {
        Clear();
        result->Success();
        return;
      }
      auto ids = Field(*args, "blockedApps"), title = Field(*args, "taskTitle"),
           expiry = Field(*args, "expiresAt"),
           remaining = Field(*args, "remainingSeconds");
      if (!ids || !std::holds_alternative<flutter::EncodableList>(*ids) ||
          !title || !std::holds_alternative<std::string>(*title) || !expiry ||
          !std::holds_alternative<std::string>(*expiry) || !remaining ||
          !std::holds_alternative<int32_t>(*remaining)) {
        result->Error("invalid_protection", "Invalid protection snapshot.");
        return;
      }
      std::set<std::string> next;
      const auto &list = std::get<flutter::EncodableList>(*ids);
      if (list.size() > 4096 || std::get<std::string>(*title).size() > 16384 ||
          std::get<int32_t>(*remaining) < 0) {
        result->Error("invalid_protection",
                      "Protection snapshot is too large.");
        return;
      }
      for (const auto &item : list) {
        auto id = std::get_if<std::string>(&item);
        if (!id || id->size() > 512 ||
            id->find_first_of("/\\") != std::string::npos) {
          result->Error("invalid_protection", "Invalid app identity.");
          return;
        }
        next.insert(*id);
      }
      auto deadline = Deadline(std::get<std::string>(*expiry));
      if (!deadline) {
        result->Error("invalid_protection", "Invalid expiration.");
        return;
      }
      if (deadline <= Now()) {
        Clear();
        result->Success();
        return;
      }
      const Value *image = Field(*args, "mascotImage");
      const auto *bytes =
          image ? std::get_if<std::vector<uint8_t>>(image) : nullptr;
      if (graphics_token && bytes && !bytes->empty() &&
          bytes->size() <= 8 * 1024 * 1024) {
        IStream *stream =
            SHCreateMemStream(bytes->data(), static_cast<UINT>(bytes->size()));
        if (stream) {
          std::unique_ptr<Gdiplus::Image> decoded(
              Gdiplus::Image::FromStream(stream, FALSE));
          if (decoded && decoded->GetLastStatus() == Gdiplus::Ok) {
            mascot.reset();
            if (mascot_stream)
              mascot_stream->Release();
            mascot_stream = stream;
            mascot = std::move(decoded);
          } else
            stream->Release();
        }
      }
      const Value *counting = Field(*args, "countdown");
      countdown = !counting || !std::holds_alternative<bool>(*counting) ||
                  std::get<bool>(*counting);
      blocked = std::move(next);
      expires = deadline;
      task = Wide(std::get<std::string>(*title));
      seconds = std::get<int32_t>(*remaining);
      updated = Now();
      Inspect();
      result->Success();
    });
  }
};
} // namespace distractions
#endif
