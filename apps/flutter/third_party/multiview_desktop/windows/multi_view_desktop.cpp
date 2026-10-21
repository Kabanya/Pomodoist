// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <codecvt>
#include <dwmapi.h>
#include <map>
#include <memory>
#include <sstream>

#include "include/multi_view_desktop/multi_view_desktop.h"

#include "multi_view_desktop.h"
#include "mvd_windows_taskbar_menu.h"

#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "shcore.lib")
#pragma comment(lib, "Gdi32.lib")
#pragma comment(lib, "ole32.lib")

namespace {

    ITaskbarList3 *GetTaskbarList() {
        static ITaskbarList3 *taskbar = nullptr;
        static bool init_failed = false;
        if (init_failed) {
            return nullptr;
        }
        if (taskbar != nullptr) {
            return taskbar;
        }
        if (FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&taskbar)))) {
            init_failed = true;
            return nullptr;
        }
        taskbar->HrInit();
        return taskbar;
    }

    void ApplyTaskbarTabVisibility(HWND hwnd, bool hide_from_taskbar) {
        if (!hwnd) {
            return;
        }
        ITaskbarList3 *taskbar = GetTaskbarList();
        if (!taskbar) {
            return;
        }
        taskbar->HrInit();
        if (hide_from_taskbar) {
            taskbar->DeleteTab(hwnd);
        } else {
            taskbar->AddTab(hwnd);
        }
    }

    void SetTaskbarProgress(HWND hWnd, double progress) {
        if (!hWnd) {
            return;
        }
        ITaskbarList3 *taskbar = GetTaskbarList();
        if (!taskbar) {
            return;
        }
        taskbar->HrInit();

        if (progress < 0) {
            taskbar->SetProgressState(hWnd, TBPF_NOPROGRESS);
            taskbar->SetProgressValue(hWnd, static_cast<int32_t>(0),
                                      static_cast<int32_t>(0));
        } else if (progress > 1) {
            taskbar->SetProgressState(hWnd, TBPF_INDETERMINATE);
            taskbar->SetProgressValue(hWnd, static_cast<int32_t>(100),
                                      static_cast<int32_t>(100));
        } else {
            taskbar->SetProgressState(hWnd, TBPF_INDETERMINATE);
            taskbar->SetProgressValue(hWnd, static_cast<int32_t>(progress * 100),
                                      static_cast<int32_t>(100));
        }
    }


}  // namespace

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See:
/// https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] =
        L"AppsUseLightTheme";

#define APPBAR_CALLBACK WM_USER + 0x01;

constexpr const wchar_t kFlutterViewWindowClassName[] = L"FLUTTERVIEW";
constexpr const wchar_t kMultiViewHostWindowClassName[] =
        L"MULTIVIEW_DESKTOP_HOST_WINDOW";

namespace {

    void RegisterMultiViewHostWindowClass() {
        static bool registered = false;
        if (registered) {
            return;
        }
        HINSTANCE hInstance = GetModuleHandle(nullptr);
        WNDCLASSEX window_class = {};
        window_class.cbSize = sizeof(WNDCLASSEX);
        window_class.style = CS_HREDRAW | CS_VREDRAW;
        window_class.lpfnWndProc = multi_view_desktop::MultiViewDesktop::HostWndProc;
        window_class.hInstance = hInstance;
        window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
        window_class.lpszClassName = kMultiViewHostWindowClassName;
        // Load the app icon from resources so secondary windows show the
        // same icon as the main window instead of the Windows default.
        window_class.hIcon = static_cast<HICON>(
            LoadImage(hInstance, MAKEINTRESOURCE(101), IMAGE_ICON,
                      0, 0, LR_DEFAULTSIZE | LR_SHARED));
        window_class.hIconSm = static_cast<HICON>(
            LoadImage(hInstance, MAKEINTRESOURCE(101), IMAGE_ICON,
                      GetSystemMetrics(SM_CXSMICON),
                      GetSystemMetrics(SM_CYSMICON),
                      LR_SHARED));
        RegisterClassEx(&window_class);
        registered = true;
    }

    double DefaultMonitorScaleFactor() {
        POINT origin = {0, 0};
        HMONITOR monitor =
                MonitorFromPoint(origin, MONITOR_DEFAULTTONEAREST);
        const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
        return static_cast<double>(dpi) / USER_DEFAULT_SCREEN_DPI;
    }

}  // namespace

namespace multi_view_desktop {

    FlutterDesktopEngineRef MultiViewDesktop::engine_ = nullptr;
    HWND MultiViewDesktop::main_host_window_ = nullptr;
    int64_t MultiViewDesktop::main_view_id_ = -1;
    bool MultiViewDesktop::terminate_after_last_window_closed_ = true;
    std::map <int64_t, std::unique_ptr<MultiViewDesktop>> MultiViewDesktop::windows_;
    std::unique_ptr <flutter::MethodChannel<flutter::EncodableValue>>
            MultiViewDesktop::channel_;

    const flutter::EncodableValue *ValueOrNull(const flutter::EncodableMap &map,
                                               const char *key) {
        auto it = map.find(flutter::EncodableValue(key));
        if (it == map.end()) {
            return nullptr;
        }
        return &(it->second);
    }

    MultiViewDesktop::MultiViewDesktop() {}

    MultiViewDesktop::~MultiViewDesktop() {}

    MultiViewDesktop &MultiViewDesktop::Instance() {
        static MultiViewDesktop instance;
        return instance;
    }

    void MultiViewDesktop::SetEngine(FlutterDesktopEngineRef engine) {
        engine_ = engine;
    }

    void MultiViewDesktop::ResizeFlutterContent(MultiViewDesktop *window) {
        if (window == nullptr || window->controller == nullptr ||
            window->native_window == nullptr) {
            return;
        }
        FlutterDesktopViewRef view =
                FlutterDesktopViewControllerGetView(window->controller);
        if (view == nullptr) {
            return;
        }
        HWND flutter_hwnd = FlutterDesktopViewGetHWND(view);
        if (flutter_hwnd == nullptr) {
            return;
        }
        RECT client_rect{};
        GetClientRect(window->native_window, &client_rect);
        const int width = client_rect.right - client_rect.left;
        const int height = client_rect.bottom - client_rect.top;
        if (width <= 0 || height <= 0) {
            return;
        }
        MoveWindow(flutter_hwnd, client_rect.left, client_rect.top, width, height,
                   TRUE);
        FlutterDesktopViewControllerForceRedraw(window->controller);
    }

    HWND MultiViewDesktop::CreateHostTopLevelWindow(const std::wstring &title,
                                                    int client_width,
                                                    int client_height) {
        RegisterMultiViewHostWindowClass();
        RECT rect = {0, 0, client_width, client_height};
        const DWORD style = WS_OVERLAPPEDWINDOW;
        AdjustWindowRect(&rect, style, FALSE);
        const int window_width = rect.right - rect.left;
        const int window_height = rect.bottom - rect.top;
        HWND hwnd = CreateWindowEx(
                0, kMultiViewHostWindowClassName, title.c_str(), style, CW_USEDEFAULT,
                CW_USEDEFAULT, window_width, window_height, nullptr, nullptr,
                GetModuleHandle(nullptr), nullptr);
        return hwnd;
    }

    HWND MultiViewDesktop::CreateDialogHostWindow(const std::wstring &title,
                                                  int client_width,
                                                  int client_height,
                                                  bool is_modal,
                                                  bool show_close_button,
                                                  HWND owner_hwnd) {
        RegisterMultiViewHostWindowClass();
        DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_THICKFRAME;
        // WS_SYSMENU is required for the title-bar close button on Windows.
        // Modal dialogs omit it; modeless dialogs include it when enabled.
        if (!is_modal && show_close_button) {
            style |= WS_SYSMENU;
        }
        const DWORD ex_style = WS_EX_DLGMODALFRAME;
        RECT rect = {0, 0, client_width, client_height};
        AdjustWindowRect(&rect, style, FALSE);
        const int window_width = rect.right - rect.left;
        const int window_height = rect.bottom - rect.top;
        HWND owner = (is_modal && owner_hwnd != nullptr) ? owner_hwnd : nullptr;
        HWND hwnd = CreateWindowEx(
                ex_style, kMultiViewHostWindowClassName, title.c_str(), style,
                CW_USEDEFAULT, CW_USEDEFAULT, window_width, window_height, owner,
                nullptr, GetModuleHandle(nullptr), nullptr);
        if (hwnd && is_modal) {
            HMENU system_menu = GetSystemMenu(hwnd, FALSE);
            if (system_menu) {
                EnableMenuItem(system_menu, SC_CLOSE, MF_BYCOMMAND | MF_GRAYED);
            }
        }
        return hwnd;
    }

    void MultiViewDesktop::CenterDialogOnOwner(HWND dialog_hwnd, HWND owner_hwnd) {
        if (!dialog_hwnd || !owner_hwnd) {
            return;
        }
        RECT owner_frame{};
        DwmGetWindowAttribute(owner_hwnd, DWMWA_EXTENDED_FRAME_BOUNDS,
                              &owner_frame, sizeof(owner_frame));
        RECT dialog_rect{};
        GetWindowRect(dialog_hwnd, &dialog_rect);
        const int dialog_width = dialog_rect.right - dialog_rect.left;
        const int dialog_height = dialog_rect.bottom - dialog_rect.top;
        const int x =
                owner_frame.left + (owner_frame.right - owner_frame.left - dialog_width) / 2;
        const int y =
                owner_frame.top + (owner_frame.bottom - owner_frame.top - dialog_height) / 2;
        SetWindowPos(dialog_hwnd, nullptr, x, y, 0, 0,
                     SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER);
    }

    namespace {

        struct OwnedModalEnumData {
            HWND owner_hwnd;
            std::vector<HWND> *owned_hwnds;
        };

        BOOL CALLBACK CollectOwnedModalWindows(HWND hwnd, LPARAM lparam) {
            auto *data = reinterpret_cast<OwnedModalEnumData *>(lparam);
            if (GetWindow(hwnd, GW_OWNER) != data->owner_hwnd) {
                return TRUE;
            }
            if (multi_view_desktop::MultiViewDesktop::Instance().FindByHwnd(hwnd) ==
                nullptr) {
                return TRUE;
            }
            data->owned_hwnds->push_back(hwnd);
            return TRUE;
        }

        std::vector<HWND> GetOwnedModalHwnds(HWND owner_hwnd) {
            std::vector<HWND> owned;
            OwnedModalEnumData data{owner_hwnd, &owned};
            EnumWindows(CollectOwnedModalWindows, reinterpret_cast<LPARAM>(&data));
            return owned;
        }

        void DisableOwnedWindowTree(HWND hwnd) {
            EnableWindow(hwnd, FALSE);
            for (HWND owned : GetOwnedModalHwnds(hwnd)) {
                DisableOwnedWindowTree(owned);
            }
        }

        int64_t ViewIdForHostHwnd(HWND hwnd) {
            MultiViewDesktop *entry =
                    MultiViewDesktop::Instance().FindByHwnd(hwnd);
            return entry != nullptr ? entry->view_id : -1;
        }

        HWND GetActiveModalFocusTarget(HWND owner_hwnd) {
            if (!owner_hwnd || !IsWindow(owner_hwnd)) {
                return nullptr;
            }
            const std::vector<HWND> owned = GetOwnedModalHwnds(owner_hwnd);
            if (owned.empty()) {
                return owner_hwnd;
            }

            HWND latest_child = owned.front();
            int64_t latest_view_id = ViewIdForHostHwnd(latest_child);
            for (HWND child : owned) {
                const int64_t child_view_id = ViewIdForHostHwnd(child);
                if (child_view_id > latest_view_id) {
                    latest_view_id = child_view_id;
                    latest_child = child;
                }
            }
            return GetActiveModalFocusTarget(latest_child);
        }

        void FocusHostWindow(HWND host_hwnd) {
            if (!host_hwnd || !IsWindow(host_hwnd) || !IsWindowEnabled(host_hwnd)) {
                return;
            }
            MultiViewDesktop *entry =
                    MultiViewDesktop::Instance().FindByHwnd(host_hwnd);
            if (entry == nullptr) {
                return;
            }

            if (entry->IsMinimized()) {
                entry->Restore();
            }

            HWND foreground = GetForegroundWindow();
            DWORD foreground_thread =
                    foreground ? GetWindowThreadProcessId(foreground, nullptr) : 0;
            DWORD target_thread = GetWindowThreadProcessId(host_hwnd, nullptr);
            const bool attach =
                    foreground_thread != 0 && foreground_thread != target_thread;
            if (attach) {
                AttachThreadInput(foreground_thread, target_thread, TRUE);
            }

            AllowSetForegroundWindow(ASFW_ANY);
            SetWindowPos(host_hwnd, HWND_TOP, 0, 0, 0, 0,
                         SWP_NOSIZE | SWP_NOMOVE | SWP_SHOWWINDOW);
            BringWindowToTop(host_hwnd);
            SetForegroundWindow(host_hwnd);
            SetActiveWindow(host_hwnd);

            if (attach) {
                AttachThreadInput(foreground_thread, target_thread, FALSE);
            }

            if (entry->controller != nullptr) {
                FlutterDesktopViewRef view =
                        FlutterDesktopViewControllerGetView(entry->controller);
                HWND flutter_hwnd = FlutterDesktopViewGetHWND(view);
                if (flutter_hwnd != nullptr) {
                    SetFocus(flutter_hwnd);
                }
            }
        }

    }  // namespace

    void MultiViewDesktop::UpdateModalStateLayer(HWND owner_hwnd) {
        if (!owner_hwnd || !IsWindow(owner_hwnd)) {
            return;
        }

        const std::vector<HWND> owned = GetOwnedModalHwnds(owner_hwnd);
        if (owned.empty()) {
            EnableWindow(owner_hwnd, TRUE);
            return;
        }

        EnableWindow(owner_hwnd, FALSE);

        HWND latest_child = owned.front();
        int64_t latest_view_id = ViewIdForHostHwnd(latest_child);
        for (HWND child : owned) {
            const int64_t child_view_id = ViewIdForHostHwnd(child);
            if (child_view_id > latest_view_id) {
                latest_view_id = child_view_id;
                latest_child = child;
            }
        }

        for (HWND child : owned) {
            if (child == latest_child) {
                UpdateModalStateLayer(child);
            } else {
                DisableOwnedWindowTree(child);
            }
        }
    }

    LRESULT CALLBACK
    MultiViewDesktop::HostWndProc(HWND
    hwnd,
    UINT message,
            WPARAM
    wparam,
    LPARAM lparam
    ) {
    LRESULT result = 0;
    if (
    MultiViewDesktopHandleWindowProc(hwnd, message, wparam, lparam, &result
    )) {
    return
    result;
}

switch (message) {
case WM_SIZE: {
MultiViewDesktop *window =
        MultiViewDesktop::Instance().FindByHwnd(hwnd);
ResizeFlutterContent(window);
return 0;
}
case WM_ACTIVATE:
if (
LOWORD(wparam)
!= WA_INACTIVE) {
MultiViewDesktop *window =
        MultiViewDesktop::Instance().FindByHwnd(hwnd);
if (window !=
nullptr &&window
->controller != nullptr) {
FlutterDesktopViewRef view =
        FlutterDesktopViewControllerGetView(window->controller);
HWND flutter_hwnd = FlutterDesktopViewGetHWND(view);
if (flutter_hwnd != nullptr) {
SetFocus(flutter_hwnd);
}
}
}
return 0;
default:
break;
}

return
DefWindowProc(hwnd, message, wparam, lparam
);
}

void MultiViewDesktop::SetupChannel(flutter::BinaryMessenger *messenger) {
    channel_ = std::make_unique < flutter::MethodChannel < flutter::EncodableValue >> (
            messenger, "multiview_desktop", &flutter::StandardMethodCodec::GetInstance());
}

void MultiViewDesktop::RegisterMain(HWND window,
                                    int64_t flutter_view_id,
                                    FlutterDesktopViewControllerRef view_controller) {
    auto entry = std::make_unique<MultiViewDesktop>();
    entry->view_id = flutter_view_id;
    entry->native_window = window;
    entry->controller = view_controller;
    entry->pixel_ratio_ = GetDpiForHwnd(window) / 96.0;
    windows_[flutter_view_id] = std::move(entry);
    main_view_id_ = flutter_view_id;
    MvdWindowsApplyAppUserModelIdToWindow(window);
}

void MultiViewDesktop::RegisterWindow(HWND window,
                                      int64_t flutter_view_id,
                                      FlutterDesktopViewControllerRef view_controller) {
    auto entry = std::make_unique<MultiViewDesktop>();
    entry->view_id = flutter_view_id;
    entry->native_window = window;
    entry->controller = view_controller;
    entry->pixel_ratio_ = GetDpiForHwnd(window) / 96.0;
    windows_[flutter_view_id] = std::move(entry);
    MvdWindowsApplyAppUserModelIdToWindow(window);
}

MultiViewDesktop *MultiViewDesktop::FindByViewId(int64_t target_view_id) {
    auto it = windows_.find(target_view_id);
    return it != windows_.end() ? it->second.get() : nullptr;
}

MultiViewDesktop *MultiViewDesktop::FindByHwnd(HWND hwnd) {
    for (auto &pair: windows_) {
        if (pair.second->native_window == hwnd) {
            return pair.second.get();
        }
    }
    return nullptr;
}

int64_t MultiViewDesktop::ViewIdForHwnd(HWND hwnd) const {
    for (const auto &pair: windows_) {
        if (pair.second->native_window == hwnd) {
            return pair.first;
        }
    }
    return -1;
}

void MultiViewDesktop::DestroyEntry(int64_t target_view_id) {
    auto it = windows_.find(target_view_id);
    if (it == windows_.end()) {
        return;
    }
    const int64_t modal_owner_id =
            it->second->is_modal_ ? it->second->modal_owner_view_id_ : -1;
    HWND host_window = it->second->native_window;
    if (it->second->controller) {
        FlutterDesktopViewControllerDestroy(it->second->controller);
        it->second->controller = nullptr;
    }
    windows_.erase(it);
    if (host_window != nullptr && IsWindow(host_window)) {
        if (host_window == main_host_window_) {
            main_host_window_ = nullptr;
        }
        DestroyWindow(host_window);
    }
    if (modal_owner_id >= 0) {
        MultiViewDesktop *owner = FindByViewId(modal_owner_id);
        if (owner != nullptr && owner->native_window != nullptr) {
            const HWND owner_hwnd = owner->native_window;
            UpdateModalStateLayer(owner_hwnd);
            FocusHostWindow(GetActiveModalFocusTarget(owner_hwnd));
        }
    }
}

void MultiViewDesktop::EmitEvent(const std::string &event_name,
                                 int64_t target_view_id) {
    if (!channel_) {
        return;
    }
    channel_->InvokeMethod(
            "onEvent",
            std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
                    {flutter::EncodableValue("eventName"),
                            flutter::EncodableValue(event_name)},
                    {flutter::EncodableValue("viewId"),
                            flutter::EncodableValue(target_view_id)},
            }));
}

void MultiViewDesktop::EmitTaskbarMenuItemSelected(int menu_item_id) {
    if (!channel_) {
        return;
    }
    channel_->InvokeMethod(
            "onEvent",
            std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
                    {flutter::EncodableValue("eventName"),
                            flutter::EncodableValue("taskbarMenuItemSelected")},
                    {flutter::EncodableValue("id"),
                            flutter::EncodableValue(menu_item_id)},
            }));
}

int64_t MultiViewDesktop::Int64FromMap(const flutter::EncodableMap &args,
                                       const char *key) {
    auto it = args.find(flutter::EncodableValue(key));
    if (it == args.end()) {
        return -1;
    }
    if (const auto *value = std::get_if<int32_t>(&it->second)) {
        return *value;
    }
    if (const auto *value = std::get_if<int64_t>(&it->second)) {
        return *value;
    }
    return -1;
}

double MultiViewDesktop::DoubleFromMap(const flutter::EncodableMap &args,
                                       const char *key,
                                       double fallback) {
    auto it = args.find(flutter::EncodableValue(key));
    if (it == args.end()) {
        return fallback;
    }
    if (const auto *value = std::get_if<double>(&it->second)) {
        return *value;
    }
    if (const auto *value = std::get_if<int32_t>(&it->second)) {
        return static_cast<double>(*value);
    }
    return fallback;
}

bool MultiViewDesktop::BoolFromMap(const flutter::EncodableMap &args,
                                   const char *key,
                                   bool fallback) {
    auto it = args.find(flutter::EncodableValue(key));
    if (it == args.end()) {
        return fallback;
    }
    if (const auto *value = std::get_if<bool>(&it->second)) {
        return *value;
    }
    return fallback;
}

std::string MultiViewDesktop::StringFromMap(const flutter::EncodableMap &args,
                                            const char *key,
                                            const std::string &fallback) {
    auto it = args.find(flutter::EncodableValue(key));
    if (it == args.end()) {
        return fallback;
    }
    if (const auto *value = std::get_if<std::string>(&it->second)) {
        return *value;
    }
    return fallback;
}

void MultiViewDesktop::CreateSecondaryWindow(const flutter::EncodableMap &args) {
    if (!engine_) {
        return;
    }

    const int token = static_cast<int>(Int64FromMap(args, "token"));
    const double width = DoubleFromMap(args, "width", 800);
    const double height = DoubleFromMap(args, "height", 600);
    const std::string title = StringFromMap(args, "title");
    const std::string title_bar_style = StringFromMap(args, "titleBarStyle", "normal");
    const bool window_button_visibility =
            BoolFromMap(args, "windowButtonVisibility", true);

    const double scale = DefaultMonitorScaleFactor();
    const int client_width = static_cast<int>(width * scale);
    const int client_height = static_cast<int>(height * scale);

    std::wstring_convert <std::codecvt_utf8_utf16<wchar_t>> converter;
    const std::wstring wide_title = converter.from_bytes(title);

    HWND host_hwnd =
            CreateHostTopLevelWindow(wide_title, client_width, client_height);
    if (!host_hwnd) {
        return;
    }

    FlutterDesktopViewControllerProperties properties = {
            client_width,
            client_height,
    };
    FlutterDesktopViewControllerRef view_controller =
            FlutterDesktopEngineCreateViewController(engine_, &properties);
    if (!view_controller) {
        DestroyWindow(host_hwnd);
        return;
    }

    const int64_t flutter_view_id =
            static_cast<int64_t>(FlutterDesktopViewControllerGetViewId(view_controller));
    FlutterDesktopViewRef view = FlutterDesktopViewControllerGetView(view_controller);
    HWND flutter_hwnd = FlutterDesktopViewGetHWND(view);
    SetParent(flutter_hwnd, host_hwnd);

    RegisterWindow(host_hwnd, flutter_view_id, view_controller);
    auto *window = FindByViewId(flutter_view_id);
    if (window) {
        window->pixel_ratio_ = scale;
        window->focus_on_show_ = BoolFromMap(args, "focusOnShow", true);
    }
    ResizeFlutterContent(window);
    if (window) {
        window->title_bar_style_ = title_bar_style;
        window->window_button_visibility_ = window_button_visibility;
        flutter::EncodableMap title_args = {
                {flutter::EncodableValue("title"), flutter::EncodableValue(title)}};
        window->SetTitle(title_args);
        if (title_bar_style == "hidden") {
            window->SetTitleBarStyle({
                                             {flutter::EncodableValue("titleBarStyle"),
                                                     flutter::EncodableValue(title_bar_style)},
                                             {flutter::EncodableValue("windowButtonVisibility"),
                                                     flutter::EncodableValue(
                                                             window_button_visibility)},
                                     });
        }
    }

    const auto *position = std::get_if<flutter::EncodableMap>(
            ValueOrNull(args, "position"));
    if (position != nullptr && window) {
        flutter::EncodableMap pos_args = *position;
        window->SetPosition(pos_args);
    } else if (window) {
        window->Center();
    }

    if (window && window->focus_on_show_) {
        ShowWindow(host_hwnd, SW_SHOW);
        SetForegroundWindow(host_hwnd);
    }
    FlutterDesktopViewControllerForceRedraw(view_controller);

    if (channel_) {
        channel_->InvokeMethod(
                "onEvent",
                std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
                        {flutter::EncodableValue("eventName"),
                                flutter::EncodableValue("viewCreated")},
                        {flutter::EncodableValue("viewId"),
                                flutter::EncodableValue(
                                        flutter_view_id)},
                        {flutter::EncodableValue("token"), flutter::EncodableValue(token)},
                }));
    }
}

void MultiViewDesktop::CreateModalDialogWindow(
        const flutter::EncodableMap &args) {
    if (!engine_) {
        return;
    }

    const int token = static_cast<int>(Int64FromMap(args, "token"));
    const int64_t parent_id = Int64FromMap(args, "parentId");
    const bool is_modal = BoolFromMap(args, "modal", false);
    const double width = DoubleFromMap(args, "width", 400);
    const double height = DoubleFromMap(args, "height", 300);
    const std::string title = StringFromMap(args, "title");
    const std::string title_bar_style = StringFromMap(args, "titleBarStyle", "normal");
    const bool window_button_visibility =
            BoolFromMap(args, "windowButtonVisibility", true);

    MultiViewDesktop *parent = FindByViewId(parent_id);
    if (is_modal && parent == nullptr) {
        return;
    }

    const double scale = DefaultMonitorScaleFactor();
    const int client_width = static_cast<int>(width * scale);
    const int client_height = static_cast<int>(height * scale);

    std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;
    const std::wstring wide_title = converter.from_bytes(title);

    HWND parent_hwnd = parent != nullptr ? parent->native_window : nullptr;
    const bool show_close_button = !is_modal && window_button_visibility;
    HWND host_hwnd = CreateDialogHostWindow(
            wide_title, client_width, client_height, is_modal, show_close_button,
            parent_hwnd);
    if (!host_hwnd) {
        return;
    }

    FlutterDesktopViewControllerProperties properties = {
            client_width,
            client_height,
    };
    FlutterDesktopViewControllerRef view_controller =
            FlutterDesktopEngineCreateViewController(engine_, &properties);
    if (!view_controller) {
        DestroyWindow(host_hwnd);
        return;
    }

    const int64_t flutter_view_id =
            static_cast<int64_t>(FlutterDesktopViewControllerGetViewId(view_controller));
    FlutterDesktopViewRef view = FlutterDesktopViewControllerGetView(view_controller);
    HWND flutter_hwnd = FlutterDesktopViewGetHWND(view);
    SetParent(flutter_hwnd, host_hwnd);

    RegisterWindow(host_hwnd, flutter_view_id, view_controller);
    auto *window = FindByViewId(flutter_view_id);
    if (window) {
        window->pixel_ratio_ = scale;
        window->is_dialog_ = true;
        window->is_modal_ = is_modal;
        window->modal_owner_view_id_ = is_modal ? parent_id : -1;
    }
    ResizeFlutterContent(window);
    if (window) {
        window->title_bar_style_ = title_bar_style;
        window->window_button_visibility_ = window_button_visibility;
        flutter::EncodableMap title_args = {
                {flutter::EncodableValue("title"), flutter::EncodableValue(title)}};
        window->SetTitle(title_args);
        if (title_bar_style == "hidden") {
            window->SetTitleBarStyle({
                    {flutter::EncodableValue("titleBarStyle"),
                            flutter::EncodableValue(title_bar_style)},
                    {flutter::EncodableValue("windowButtonVisibility"),
                            flutter::EncodableValue(window_button_visibility)},
                    {flutter::EncodableValue("maximizeVisibility"),
                            flutter::EncodableValue(false)},
                    {flutter::EncodableValue("minimizeVisibility"),
                            flutter::EncodableValue(false)},
            });
        } else {
            window->SetTitleBarStyle({
                    {flutter::EncodableValue("titleBarStyle"),
                            flutter::EncodableValue(title_bar_style)},
                    {flutter::EncodableValue("windowButtonVisibility"),
                            flutter::EncodableValue(window_button_visibility)},
                    {flutter::EncodableValue("maximizeVisibility"),
                            flutter::EncodableValue(false)},
                    {flutter::EncodableValue("minimizeVisibility"),
                            flutter::EncodableValue(false)},
            });
        }
    }

    if (is_modal && parent_hwnd != nullptr) {
        CenterDialogOnOwner(host_hwnd, parent_hwnd);
    } else {
        const auto *position = std::get_if<flutter::EncodableMap>(
                ValueOrNull(args, "position"));
        if (position != nullptr && window) {
            flutter::EncodableMap pos_args = *position;
            window->SetPosition(pos_args);
        } else if (parent_hwnd != nullptr) {
            CenterDialogOnOwner(host_hwnd, parent_hwnd);
        } else if (window) {
            window->Center();
        }
    }

    if (is_modal) {
        ShowWindow(host_hwnd, SW_SHOW);
        SetForegroundWindow(host_hwnd);
        if (parent_hwnd != nullptr) {
            UpdateModalStateLayer(parent_hwnd);
        }
        FlutterDesktopViewControllerForceRedraw(view_controller);
    }

    if (channel_) {
        channel_->InvokeMethod(
                "onEvent",
                std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
                        {flutter::EncodableValue("eventName"),
                                flutter::EncodableValue("viewCreated")},
                        {flutter::EncodableValue("viewId"),
                                flutter::EncodableValue(flutter_view_id)},
                        {flutter::EncodableValue("token"), flutter::EncodableValue(token)},
                }));
    }
}

HWND MultiViewDesktop::GetMainWindow() {
    return native_window;
}

void MultiViewDesktop::ForceRefresh() {
    HWND hWnd = GetMainWindow();

    RECT rect;

    GetWindowRect(hWnd, &rect);
    SetWindowPos(
            hWnd, nullptr, rect.left, rect.top, rect.right - rect.left + 1,
            rect.bottom - rect.top,
            SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOMOVE | SWP_FRAMECHANGED);
    SetWindowPos(
            hWnd, nullptr, rect.left, rect.top, rect.right - rect.left,
            rect.bottom - rect.top,
            SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOMOVE | SWP_FRAMECHANGED);
}

void MultiViewDesktop::ForceChildRefresh() {
    HWND hWnd = GetWindow(GetMainWindow(), GW_CHILD);

    RECT rect;

    GetWindowRect(hWnd, &rect);
    SetWindowPos(
            hWnd, nullptr, rect.left, rect.top, rect.right - rect.left + 1,
            rect.bottom - rect.top,
            SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOMOVE | SWP_FRAMECHANGED);
    SetWindowPos(
            hWnd, nullptr, rect.left, rect.top, rect.right - rect.left,
            rect.bottom - rect.top,
            SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOMOVE | SWP_FRAMECHANGED);
}

void MultiViewDesktop::SetAsFrameless() {
    is_frameless_ = true;
    HWND hWnd = GetMainWindow();

    RECT rect;

    GetWindowRect(hWnd, &rect);
    SetWindowPos(hWnd, nullptr, rect.left, rect.top, rect.right - rect.left,
                 rect.bottom - rect.top,
                 (focus_on_show_ ? 0 : SWP_NOACTIVATE) | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOMOVE | SWP_NOSIZE |
                 SWP_FRAMECHANGED);
}

void MultiViewDesktop::Close() {
    PostMessage(GetMainWindow(), WM_CLOSE, 0, 0);
}

void MultiViewDesktop::SetConfirmClose(const flutter::EncodableMap &args) {
    is_confirm_close_ = std::get<bool>(args.at(flutter::EncodableValue("confirmClose")));
}

bool MultiViewDesktop::IsConfirmClose() {
    return is_confirm_close_;
}

void MultiViewDesktop::SetPreventClose(const flutter::EncodableMap &args) {
    is_prevent_close_ =
            std::get<bool>(args.at(flutter::EncodableValue("isPreventClose")));
}

void MultiViewDesktop::SetProgressBar(double progress) {
//    double progress =
//            std::get<double>(args.at(flutter::EncodableValue("progress")));

    HWND hWnd = GetMainWindow();
    SetTaskbarProgress(hWnd, progress);
}

bool MultiViewDesktop::IsPreventClose() {
    return is_prevent_close_;
}

void MultiViewDesktop::SetPreConfirmClose(const flutter::EncodableMap &args) {
    is_pre_confirm_ =
            std::get<bool>(args.at(flutter::EncodableValue("preConfirmClose")));
}

void MultiViewDesktop::Focus() {
    HWND hWnd = GetMainWindow();
    if (IsMinimized()) {
        Restore();
    }

    ::SetWindowPos(hWnd, HWND_TOP, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE);
    SetForegroundWindow(hWnd);
}

void MultiViewDesktop::Blur() {
    HWND hWnd = GetMainWindow();
    HWND next_hwnd = ::GetNextWindow(hWnd, GW_HWNDNEXT);
    while (next_hwnd) {
        if (::IsWindowVisible(next_hwnd)) {
            ::SetForegroundWindow(next_hwnd);
            return;
        }
        next_hwnd = ::GetNextWindow(next_hwnd, GW_HWNDNEXT);
    }
}

bool MultiViewDesktop::IsFocused() {
    return GetMainWindow() == GetForegroundWindow();
}

void MultiViewDesktop::Show() {
    HWND hWnd = GetMainWindow();
    DWORD gwlStyle = GetWindowLong(hWnd, GWL_STYLE);
    gwlStyle = gwlStyle | WS_VISIBLE;
    if ((gwlStyle & WS_VISIBLE) == 0) {
        SetWindowLong(hWnd, GWL_STYLE, gwlStyle);
        ::SetWindowPos(hWnd, HWND_TOP, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE);
    }

    ShowWindowAsync(GetMainWindow(), focus_on_show_ ? SW_SHOW : SW_SHOWNOACTIVATE);
    if (focus_on_show_) SetForegroundWindow(GetMainWindow());
    if (is_skip_taskbar_) {
        ApplyTaskbarTabVisibility(hWnd, true);
    }
}

void MultiViewDesktop::Hide() {
    ShowWindow(GetMainWindow(), SW_HIDE);
}

bool MultiViewDesktop::IsVisible() {
    bool isVisible = IsWindowVisible(GetMainWindow());
    return isVisible;
}

bool MultiViewDesktop::IsMaximized() {
    HWND mainWindow = GetMainWindow();
    WINDOWPLACEMENT windowPlacement;
    GetWindowPlacement(mainWindow, &windowPlacement);

    return windowPlacement.showCmd == SW_MAXIMIZE;
}

void MultiViewDesktop::Maximize(const flutter::EncodableMap &args) {
    if (is_dialog_) {
        return;
    }
    bool vertically =
            std::get<bool>(args.at(flutter::EncodableValue("vertically")));

    HWND hwnd = GetMainWindow();
    WINDOWPLACEMENT windowPlacement;
    GetWindowPlacement(hwnd, &windowPlacement);

    if (vertically) {
        POINT cursorPos;
        GetCursorPos(&cursorPos);
        PostMessage(hwnd, WM_NCLBUTTONDBLCLK, HTTOP,
                    MAKELPARAM(cursorPos.x, cursorPos.y));
    } else {
        if (windowPlacement.showCmd != SW_MAXIMIZE) {
            PostMessage(hwnd, WM_SYSCOMMAND, SC_MAXIMIZE, 0);
        }
    }
}

void MultiViewDesktop::Unmaximize() {
    HWND mainWindow = GetMainWindow();
    WINDOWPLACEMENT windowPlacement;
    GetWindowPlacement(mainWindow, &windowPlacement);

    if (windowPlacement.showCmd != SW_NORMAL) {
        PostMessage(mainWindow, WM_SYSCOMMAND, SC_RESTORE, 0);
    }
}

bool MultiViewDesktop::IsMinimized() {
    HWND mainWindow = GetMainWindow();
    WINDOWPLACEMENT windowPlacement;
    GetWindowPlacement(mainWindow, &windowPlacement);

    return windowPlacement.showCmd == SW_SHOWMINIMIZED;
}

void MultiViewDesktop::Minimize() {
    if (is_dialog_) {
        return;
    }
    if (IsFullScreen()) {  // Like chromium, we don't want to minimize fullscreen
        // windows
        return;
    }
    HWND mainWindow = GetMainWindow();
    WINDOWPLACEMENT windowPlacement;
    GetWindowPlacement(mainWindow, &windowPlacement);

    if (windowPlacement.showCmd != SW_SHOWMINIMIZED) {
        PostMessage(mainWindow, WM_SYSCOMMAND, SC_MINIMIZE, 0);
    }
}

void MultiViewDesktop::Restore() {
    HWND mainWindow = GetMainWindow();
    WINDOWPLACEMENT windowPlacement;
    GetWindowPlacement(mainWindow, &windowPlacement);

    if (windowPlacement.showCmd != SW_NORMAL) {
        PostMessage(mainWindow, WM_SYSCOMMAND, SC_RESTORE, 0);
    }
}

double MultiViewDesktop::GetDpiForHwnd(HWND hWnd) {
    auto monitor = MonitorFromWindow(hWnd, MONITOR_DEFAULTTONEAREST);
    UINT newDpiX = 96;  // Default values
    UINT newDpiY = 96;

    // Dynamically load shcore.dll and get the GetDpiForMonitor function address
    // We need to do this to ensure Windows 7 support
    HMODULE shcore = LoadLibrary(TEXT("shcore.dll"));
    if (shcore) {
        typedef HRESULT (*GetDpiForMonitor)(HMONITOR, int, UINT *, UINT *);

        GetDpiForMonitor GetDpiForMonitorFunc =
                (GetDpiForMonitor) GetProcAddress(shcore, "GetDpiForMonitor");

        if (GetDpiForMonitorFunc) {
            // Use the loaded function if available
            const int MDT_EFFECTIVE_DPI = 0;
            if (FAILED(GetDpiForMonitorFunc(monitor, MDT_EFFECTIVE_DPI, &newDpiX,
                                            &newDpiY))) {
                // If it fails, set the default values again
                newDpiX = 96;
                newDpiY = 96;
            }
        }
        FreeLibrary(shcore);
    }
    return ((double) newDpiX);
}

bool MultiViewDesktop::IsFullScreen() {
    return g_is_window_fullscreen;
}

void MultiViewDesktop::SetFullScreen(const flutter::EncodableMap &args) {
    if (is_dialog_) {
        return;
    }
    bool isFullScreen =
            std::get<bool>(args.at(flutter::EncodableValue("isFullScreen")));

    HWND mainWindow = GetMainWindow();

    // Previously inspired by how Chromium does this
    // https://src.chromium.org/viewvc/chrome/trunk/src/ui/views/win/fullscreen_handler.cc?revision=247204&view=markup
    // Instead, we use a modified implementation of how the media_kit package
    // implements this (we got permission from the author, I believe)
    // https://github.com/alexmercerind/media_kit/blob/1226bcff36eab27cb17d60c33e9c15ca489c1f06/media_kit_video/windows/utils.cc

    // Save current window state if not already fullscreen.
    if (!g_is_window_fullscreen) {
        // Save current window information.
        g_maximized_before_fullscreen = ::IsZoomed(mainWindow);
        g_style_before_fullscreen = GetWindowLong(mainWindow, GWL_STYLE);
        ::GetWindowRect(mainWindow, &g_frame_before_fullscreen);
        g_title_bar_style_before_fullscreen = title_bar_style_;
    }

    g_is_window_fullscreen = isFullScreen;

    if (isFullScreen) {  // Set to fullscreen
        ::SendMessage(mainWindow, WM_SYSCOMMAND, SC_MAXIMIZE, 0);
        if (!is_frameless_) {
            auto monitor = MONITORINFO{};
            auto placement = WINDOWPLACEMENT{};
            monitor.cbSize = sizeof(MONITORINFO);
            placement.length = sizeof(WINDOWPLACEMENT);
            ::GetWindowPlacement(mainWindow, &placement);
            ::GetMonitorInfo(
                    ::MonitorFromWindow(mainWindow, MONITOR_DEFAULTTONEAREST), &monitor);
            ::SetWindowLongPtr(mainWindow, GWL_STYLE,
                               g_style_before_fullscreen & ~WS_OVERLAPPEDWINDOW);
            ::SetWindowPos(mainWindow, HWND_TOP, monitor.rcMonitor.left,
                           monitor.rcMonitor.top,
                           monitor.rcMonitor.right - monitor.rcMonitor.left,
                           monitor.rcMonitor.bottom - monitor.rcMonitor.top,
                           SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
        }
    } else {  // Restore from fullscreen
        if (!g_maximized_before_fullscreen)
            Restore();
        ::SetWindowLongPtr(mainWindow, GWL_STYLE,
                           g_style_before_fullscreen | WS_OVERLAPPEDWINDOW);
        if (::IsZoomed(mainWindow)) {
            // Refresh the parent mainWindow.
            ::SetWindowPos(mainWindow, nullptr, 0, 0, 0, 0,
                           SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                           SWP_FRAMECHANGED);
            auto rect = RECT{};
            ::GetClientRect(mainWindow, &rect);
            auto flutter_view = ::FindWindowEx(mainWindow, nullptr,
                                               kFlutterViewWindowClassName, nullptr);
            ::SetWindowPos(flutter_view, nullptr, rect.left, rect.top,
                           rect.right - rect.left, rect.bottom - rect.top,
                           SWP_NOACTIVATE | SWP_NOZORDER);
            if (g_maximized_before_fullscreen)
                PostMessage(mainWindow, WM_SYSCOMMAND, SC_MAXIMIZE, 0);
        } else {
            ::SetWindowPos(
                    mainWindow, nullptr, g_frame_before_fullscreen.left,
                    g_frame_before_fullscreen.top,
                    g_frame_before_fullscreen.right - g_frame_before_fullscreen.left,
                    g_frame_before_fullscreen.bottom - g_frame_before_fullscreen.top,
                    SWP_NOACTIVATE | SWP_NOZORDER);
        }
    }
}

void MultiViewDesktop::SetAspectRatio(const flutter::EncodableMap &args) {
    aspect_ratio_ =
            std::get<double>(args.at(flutter::EncodableValue("aspectRatio")));
}

void MultiViewDesktop::SetBackgroundColor(const flutter::EncodableMap &args) {
    int backgroundColorA =
            std::get<int>(args.at(flutter::EncodableValue("backgroundColorA")));
    int backgroundColorR =
            std::get<int>(args.at(flutter::EncodableValue("backgroundColorR")));
    int backgroundColorG =
            std::get<int>(args.at(flutter::EncodableValue("backgroundColorG")));
    int backgroundColorB =
            std::get<int>(args.at(flutter::EncodableValue("backgroundColorB")));

    bool isTransparent = backgroundColorA == 0 && backgroundColorR == 0 &&
                         backgroundColorG == 0 && backgroundColorB == 0;

    HWND hWnd = GetMainWindow();
    const HINSTANCE hModule = LoadLibrary(TEXT("user32.dll"));
    if (hModule) {
        typedef enum _ACCENT_STATE {
            ACCENT_DISABLED = 0,
            ACCENT_ENABLE_GRADIENT = 1,
            ACCENT_ENABLE_TRANSPARENTGRADIENT = 2,
            ACCENT_ENABLE_BLURBEHIND = 3,
            ACCENT_ENABLE_ACRYLICBLURBEHIND = 4,
            ACCENT_ENABLE_HOSTBACKDROP = 5,
            ACCENT_INVALID_STATE = 6
        } ACCENT_STATE;
        struct ACCENTPOLICY {
            int nAccentState;
            int nFlags;
            int nColor;
            int nAnimationId;
        };
        struct WINCOMPATTRDATA {
            int nAttribute;
            PVOID pData;
            ULONG ulDataSize;
        };
        typedef BOOL(WINAPI
        *pSetWindowCompositionAttribute)(HWND,
                WINCOMPATTRDATA *);
        const pSetWindowCompositionAttribute SetWindowCompositionAttribute =
                (pSetWindowCompositionAttribute) GetProcAddress(
                        hModule, "SetWindowCompositionAttribute");
        if (SetWindowCompositionAttribute) {
            int32_t accent_state = isTransparent ? ACCENT_ENABLE_TRANSPARENTGRADIENT
                                                 : ACCENT_ENABLE_GRADIENT;
            ACCENTPOLICY policy = {
                    accent_state, 2,
                    ((backgroundColorA << 24) + (backgroundColorB << 16) +
                     (backgroundColorG << 8) + (backgroundColorR)),
                    0};
            WINCOMPATTRDATA data = {19, &policy, sizeof(policy)};
            SetWindowCompositionAttribute(hWnd, &data);
        }
        FreeLibrary(hModule);
    }
}

flutter::EncodableMap MultiViewDesktop::GetBounds(
        const flutter::EncodableMap &args) {
    HWND hwnd = GetMainWindow();
    const double device_pixel_ratio =
            pixel_ratio_ > 0 ? pixel_ratio_ : GetDpiForHwnd(hwnd) / 96.0;

    flutter::EncodableMap resultMap = flutter::EncodableMap();
    RECT rect;
    if (GetWindowRect(hwnd, &rect)) {
        resultMap[flutter::EncodableValue("x")] =
                flutter::EncodableValue(static_cast<double>(rect.left) / device_pixel_ratio);
        resultMap[flutter::EncodableValue("y")] =
                flutter::EncodableValue(static_cast<double>(rect.top) / device_pixel_ratio);
        resultMap[flutter::EncodableValue("width")] = flutter::EncodableValue(
                static_cast<double>(rect.right - rect.left) / device_pixel_ratio);
        resultMap[flutter::EncodableValue("height")] = flutter::EncodableValue(
                static_cast<double>(rect.bottom - rect.top) / device_pixel_ratio);
    }
    return resultMap;
}

void MultiViewDesktop::SetSize(const flutter::EncodableMap &args) {
    HWND hwnd = GetMainWindow();
    const double width = DoubleFromMap(args, "width", 0);
    const double height = DoubleFromMap(args, "height", 0);
    RECT rect{};
    GetWindowRect(hwnd, &rect);
    const int w = static_cast<int>(width * pixel_ratio_);
    const int h = static_cast<int>(height * pixel_ratio_);
    SetWindowPos(hwnd, nullptr, rect.left, rect.top, w, h,
                 (focus_on_show_ ? 0 : SWP_NOACTIVATE) | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOMOVE);
}

void MultiViewDesktop::SetPosition(const flutter::EncodableMap &args) {
    HWND hwnd = GetMainWindow();
    const double x = DoubleFromMap(args, "x", 0);
    const double y = DoubleFromMap(args, "y", 0);
    RECT rect{};
    GetWindowRect(hwnd, &rect);
    const int left = static_cast<int>(x * pixel_ratio_);
    const int top = static_cast<int>(y * pixel_ratio_);
    SetWindowPos(hwnd, nullptr, left, top, rect.right - rect.left,
                 rect.bottom - rect.top,
                 (focus_on_show_ ? 0 : SWP_NOACTIVATE) | SWP_NOZORDER | SWP_NOOWNERZORDER);
}

void MultiViewDesktop::Center() {
    HWND hwnd = GetMainWindow();
    RECT rect{};
    GetWindowRect(hwnd, &rect);
    const int width = rect.right - rect.left;
    const int height = rect.bottom - rect.top;
    const HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(MONITORINFO);
    GetMonitorInfo(monitor, &info);
    const int x = info.rcWork.left + (info.rcWork.right - info.rcWork.left - width) / 2;
    const int y = info.rcWork.top + (info.rcWork.bottom - info.rcWork.top - height) / 2;
    SetWindowPos(hwnd, nullptr, x, y, width, height,
                 (focus_on_show_ ? 0 : SWP_NOACTIVATE) | SWP_NOZORDER | SWP_NOOWNERZORDER);
}

void MultiViewDesktop::SetMinimumSize(const flutter::EncodableMap &args) {
    const double width = DoubleFromMap(args, "width", 0);
    const double height = DoubleFromMap(args, "height", 0);
    minimum_size_.x = static_cast<LONG>(width);
    minimum_size_.y = static_cast<LONG>(height);
}

void MultiViewDesktop::SetMaximumSize(const flutter::EncodableMap &args) {
    const double width = DoubleFromMap(args, "width", -1);
    const double height = DoubleFromMap(args, "height", -1);
    maximum_size_.x = static_cast<LONG>(width);
    maximum_size_.y = static_cast<LONG>(height);
}

bool MultiViewDesktop::IsResizable() {
    return is_resizable_;
}

void MultiViewDesktop::SetResizable(const flutter::EncodableMap &args) {
    HWND hWnd = GetMainWindow();
    is_resizable_ =
            std::get<bool>(args.at(flutter::EncodableValue("isResizable")));
    DWORD gwlStyle = GetWindowLong(hWnd, GWL_STYLE);
    if (is_resizable_) {
        gwlStyle |= WS_THICKFRAME;
    } else {
        gwlStyle &= ~WS_THICKFRAME;
    }
    ::SetWindowLong(hWnd, GWL_STYLE, gwlStyle);
}

bool MultiViewDesktop::IsMinimizable() {
    HWND hWnd = GetMainWindow();
    DWORD gwlStyle = GetWindowLong(hWnd, GWL_STYLE);
    return (gwlStyle & WS_MINIMIZEBOX) != 0;
}

void MultiViewDesktop::SetMinimizable(const flutter::EncodableMap &args) {
    HWND hWnd = GetMainWindow();
    bool isMinimizable =
            std::get<bool>(args.at(flutter::EncodableValue("isMinimizable")));
    DWORD gwlStyle = GetWindowLong(hWnd, GWL_STYLE);
    gwlStyle =
            isMinimizable ? gwlStyle | WS_MINIMIZEBOX : gwlStyle & ~WS_MINIMIZEBOX;
    SetWindowLong(hWnd, GWL_STYLE, gwlStyle);
}

bool MultiViewDesktop::IsMaximizable() {
    HWND hWnd = GetMainWindow();
    DWORD gwlStyle = GetWindowLong(hWnd, GWL_STYLE);
    return (gwlStyle & WS_MAXIMIZEBOX) != 0;
}

void MultiViewDesktop::SetMaximizable(const flutter::EncodableMap &args) {
    HWND hWnd = GetMainWindow();
    bool isMaximizable =
            std::get<bool>(args.at(flutter::EncodableValue("isMaximizable")));
    DWORD gwlStyle = GetWindowLong(hWnd, GWL_STYLE);
    gwlStyle =
            isMaximizable ? gwlStyle | WS_MAXIMIZEBOX : gwlStyle & ~WS_MAXIMIZEBOX;
    SetWindowLong(hWnd, GWL_STYLE, gwlStyle);
}

bool MultiViewDesktop::IsClosable() {
    HWND hWnd = GetMainWindow();
    DWORD gclStyle = GetClassLong(hWnd, GCL_STYLE);
    return !((gclStyle & CS_NOCLOSE) != 0);
}

void MultiViewDesktop::SetClosable(const flutter::EncodableMap &args) {
    HWND hWnd = GetMainWindow();
    bool isClosable =
            std::get<bool>(args.at(flutter::EncodableValue("isClosable")));
    DWORD gclStyle = GetClassLong(hWnd, GCL_STYLE);
    gclStyle = isClosable ? gclStyle & ~CS_NOCLOSE : gclStyle | CS_NOCLOSE;
    SetClassLong(hWnd, GCL_STYLE, gclStyle);
}

bool MultiViewDesktop::IsAlwaysOnTop() {
    DWORD dwExStyle = GetWindowLong(GetMainWindow(), GWL_EXSTYLE);
    return (dwExStyle & WS_EX_TOPMOST) != 0;
}

void MultiViewDesktop::SetAlwaysOnTop(const flutter::EncodableMap &args) {
    bool isAlwaysOnTop =
            std::get<bool>(args.at(flutter::EncodableValue("isAlwaysOnTop")));
    SetWindowPos(GetMainWindow(), isAlwaysOnTop ? HWND_TOPMOST : HWND_NOTOPMOST,
                 0, 0, 0, 0, (focus_on_show_ ? 0 : SWP_NOACTIVATE) | SWP_NOMOVE | SWP_NOSIZE);
}

std::string MultiViewDesktop::GetTitle() {
    int const bufferSize = 1 + GetWindowTextLength(GetMainWindow());
    std::wstring title(bufferSize, L'\0');
    GetWindowText(GetMainWindow(), &title[0], bufferSize);

    std::wstring_convert <std::codecvt_utf8_utf16<wchar_t>> converter;
    return (converter.to_bytes(title)).c_str();
}

void MultiViewDesktop::SetTitle(const flutter::EncodableMap &args) {
    std::string title =
            std::get<std::string>(args.at(flutter::EncodableValue("title")));

    std::wstring_convert <std::codecvt_utf8_utf16<wchar_t>> converter;
    SetWindowText(GetMainWindow(), converter.from_bytes(title).c_str());
}

void MultiViewDesktop::SetTitleBarStyle(const flutter::EncodableMap &args) {
    title_bar_style_ =
            std::get<std::string>(args.at(flutter::EncodableValue("titleBarStyle")));
    if (args.find(flutter::EncodableValue("windowButtonVisibility")) != args.end()) {
        window_button_visibility_ =
                std::get<bool>(args.at(flutter::EncodableValue("windowButtonVisibility")));
    }
    is_frameless_ = false;

    MARGINS margins = {0, 0, 0, 0};
    HWND hWnd = GetMainWindow();
    RECT rect;
    GetWindowRect(hWnd, &rect);
    DwmExtendFrameIntoClientArea(hWnd, &margins);
    SetWindowPos(hWnd, nullptr, rect.left, rect.top, 0, 0,
                 (focus_on_show_ ? 0 : SWP_NOACTIVATE) | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOMOVE | SWP_NOSIZE |
                 SWP_FRAMECHANGED);
}

flutter::EncodableMap MultiViewDesktop::GetTitleBarStyle() {
    return flutter::EncodableMap{
            {flutter::EncodableValue("style"),
                    flutter::EncodableValue(title_bar_style_)},
            {flutter::EncodableValue("windowButtonVisibility"),
                    flutter::EncodableValue(window_button_visibility_)},
    };
}

bool MultiViewDesktop::IsMovable() {
    return (GetWindowLong(GetMainWindow(), GWL_STYLE) & WS_CAPTION) != 0;
}

void MultiViewDesktop::SetMovable(const flutter::EncodableMap &args) {
    const bool movable =
            std::get<bool>(args.at(flutter::EncodableValue("isMovable")));
    HWND hwnd = GetMainWindow();
    LONG style = GetWindowLong(hwnd, GWL_STYLE);
    if (movable) {
        style |= WS_CAPTION;
    } else {
        style &= ~WS_CAPTION;
    }
    SetWindowLong(hwnd, GWL_STYLE, style);
}

bool MultiViewDesktop::IsSkipTaskbar() {
    return is_skip_taskbar_;
}

void MultiViewDesktop::SetSkipTaskbar(const flutter::EncodableMap &args) {
    is_skip_taskbar_ = BoolFromMap(args, "isHideAppFromTaskbar",
                                   BoolFromMap(args, "isSkipTaskbar", false));

    HWND hWnd = GetMainWindow();
    ApplyTaskbarTabVisibility(hWnd, is_skip_taskbar_);
}

bool MultiViewDesktop::HasShadow() {
    if (is_frameless_)
        return has_shadow_;
    return true;
}

void MultiViewDesktop::SetHasShadow(const flutter::EncodableMap &args) {
    if (is_frameless_) {
        has_shadow_ = std::get<bool>(args.at(flutter::EncodableValue("hasShadow")));

        HWND hWnd = GetMainWindow();

        MARGINS margins[2]{{0, 0, 0, 0},
                           {0, 0, 1, 0}};

        DwmExtendFrameIntoClientArea(hWnd, &margins[has_shadow_]);
    }
}

double MultiViewDesktop::GetOpacity() {
    return opacity_;
}

void MultiViewDesktop::SetOpacity(const flutter::EncodableMap &args) {
    opacity_ = std::get<double>(args.at(flutter::EncodableValue("opacity")));
    HWND hWnd = GetMainWindow();
    long gwlExStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
    SetWindowLong(hWnd, GWL_EXSTYLE, gwlExStyle | WS_EX_LAYERED);
    SetLayeredWindowAttributes(hWnd, 0, static_cast<int8_t>(255 * opacity_),
                               0x02);
}

void MultiViewDesktop::SetBrightness(const flutter::EncodableMap &args) {
    DWORD light_mode;
    DWORD light_mode_size = sizeof(light_mode);
    LSTATUS result =
            RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                        kGetPreferredBrightnessRegValue, RRF_RT_REG_DWORD, nullptr,
                        &light_mode, &light_mode_size);

    if (result == ERROR_SUCCESS) {
        std::string brightness =
                std::get<std::string>(args.at(flutter::EncodableValue("brightness")));
        HWND hWnd = GetMainWindow();
        BOOL enable_dark_mode = light_mode == 0 && brightness == "dark";
        DwmSetWindowAttribute(hWnd, DWMWA_USE_IMMERSIVE_DARK_MODE,
                              &enable_dark_mode, sizeof(enable_dark_mode));
    }
}

void MultiViewDesktop::SetIgnoreMouseEvents(
        const flutter::EncodableMap &args) {
    bool ignore = std::get<bool>(args.at(flutter::EncodableValue("ignore")));

    HWND hwnd = GetMainWindow();
    LONG ex_style = ::GetWindowLong(hwnd, GWL_EXSTYLE);
    if (ignore)
        ex_style |= (WS_EX_TRANSPARENT | WS_EX_LAYERED);
    else
        ex_style &= ~(WS_EX_TRANSPARENT | WS_EX_LAYERED);

    ::SetWindowLong(hwnd, GWL_EXSTYLE, ex_style);
}

flutter::EncodableMap MultiViewDesktop::IsIgnoreMouseEvents() {
    HWND hwnd = GetMainWindow();
    const LONG ex_style = ::GetWindowLong(hwnd, GWL_EXSTYLE);
    const bool ignore = (ex_style & WS_EX_TRANSPARENT) != 0;
    return flutter::EncodableMap{
            {flutter::EncodableValue("ignore"),  flutter::EncodableValue(ignore)},
            {flutter::EncodableValue("forward"), flutter::EncodableValue(false)},
    };
}

void MultiViewDesktop::PopUpWindowMenu(const flutter::EncodableMap &args) {
    HWND hWnd = GetMainWindow();
    HMENU hMenu = GetSystemMenu(hWnd, false);

    double x, y;

    POINT cursorPos;
    GetCursorPos(&cursorPos);
    x = cursorPos.x;
    y = cursorPos.y;

    int cmd =
            TrackPopupMenu(hMenu, TPM_LEFTBUTTON | TPM_RIGHTBUTTON | TPM_RETURNCMD,
                           static_cast<int>(x), static_cast<int>(y), 0, hWnd, NULL);

    if (cmd) {
        PostMessage(hWnd, WM_SYSCOMMAND, cmd, 0);
    }
}

void MultiViewDesktop::StartDragging() {
    ReleaseCapture();
    SendMessage(GetMainWindow(), WM_SYSCOMMAND, SC_MOVE | HTCAPTION, 0);
}

void MultiViewDesktop::StartResizing(const flutter::EncodableMap &args) {
    bool top = std::get<bool>(args.at(flutter::EncodableValue("top")));
    bool bottom = std::get<bool>(args.at(flutter::EncodableValue("bottom")));
    bool left = std::get<bool>(args.at(flutter::EncodableValue("left")));
    bool right = std::get<bool>(args.at(flutter::EncodableValue("right")));

    HWND hWnd = GetMainWindow();
    ReleaseCapture();
    LONG command;
    if (top && !bottom && !right && !left) {
        command = HTTOP;
    } else if (top && left && !bottom && !right) {
        command = HTTOPLEFT;
    } else if (left && !top && !bottom && !right) {
        command = HTLEFT;
    } else if (right && !top && !left && !bottom) {
        command = HTRIGHT;
    } else if (top && right && !left && !bottom) {
        command = HTTOPRIGHT;
    } else if (bottom && !top && !right && !left) {
        command = HTBOTTOM;
    } else if (bottom && left && !top && !right) {
        command = HTBOTTOMLEFT;
    } else
        command = HTBOTTOMRIGHT;
    POINT cursorPos;
    GetCursorPos(&cursorPos);
    PostMessage(hWnd, WM_NCLBUTTONDOWN, command,
                MAKELPARAM(cursorPos.x, cursorPos.y));
}

}  // namespace multi_view_desktop