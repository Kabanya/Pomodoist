#include "include/multi_view_desktop/multi_view_desktop.h"

#include <windows.h>

#include <flutter/dart_project.h>
#include <flutter/flutter_engine.h>
#include <flutter_windows.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <cmath>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "multi_view_desktop.h"
#include "mvd_windows_taskbar_menu.h"

namespace multi_view_desktop {

    namespace {

        bool IsWindows11OrGreater() {
            DWORD dw_version = 0;
            DWORD dw_build = 0;
#pragma warning(push)
#pragma warning(disable : 4996)
            dw_version = GetVersion();
            if (dw_version < 0x80000000) {
                dw_build = static_cast<DWORD>(HIWORD(dw_version));
            }
#pragma warning(pop)
            return dw_build >= 22000;
        }

        void AdjustNCCalcSize(HWND hwnd, NCCALCSIZE_PARAMS *sz) {
            LONG l = 8;
            LONG t = 8;
            HMONITOR monitor = MonitorFromRect(&sz->rgrc[0], MONITOR_DEFAULTTONEAREST);
            if (monitor != NULL) {
                MONITORINFO monitor_info;
                monitor_info.cbSize = sizeof(MONITORINFO);
                if (GetMonitorInfo(monitor, &monitor_info)) {
                    l = sz->rgrc[0].left - monitor_info.rcWork.left;
                    t = sz->rgrc[0].top - monitor_info.rcWork.top;
                }
            }
            sz->rgrc[0].left -= l;
            sz->rgrc[0].top -= t;
            sz->rgrc[0].right += l;
            sz->rgrc[0].bottom += t;
        }

    }  // namespace

    FlutterDesktopEngineProperties BuildEngineProperties(
            const flutter::DartProject &project) {
        static std::wstring assets_path = L"data\\flutter_assets";
        static std::wstring icu_data_path = L"data\\icudtl.dat";
        static std::wstring aot_library_path = L"data\\app.so";
        static std::vector <std::string> entrypoint_args_storage;
        static std::vector<const char *> entrypoint_argv;

        FlutterDesktopEngineProperties properties = {};
        properties.assets_path = assets_path.c_str();
        properties.icu_data_path = icu_data_path.c_str();
        properties.aot_library_path = aot_library_path.c_str();
        properties.dart_entrypoint = project.dart_entrypoint().empty()
                                     ? nullptr
                                     : project.dart_entrypoint().c_str();
        properties.gpu_preference = static_cast<FlutterDesktopGpuPreference>(
                project.gpu_preference());
        properties.ui_thread_policy = static_cast<FlutterDesktopUIThreadPolicy>(
                project.ui_thread_policy());
        properties.accessibility_mode = static_cast<FlutterDesktopAccessibilityMode>(
                project.accessibility_mode());

        entrypoint_args_storage = project.dart_entrypoint_arguments();
        entrypoint_argv.clear();
        for (const auto &arg: entrypoint_args_storage) {
            entrypoint_argv.push_back(arg.c_str());
        }
        properties.dart_entrypoint_argc = static_cast<int>(entrypoint_argv.size());
        properties.dart_entrypoint_argv =
                entrypoint_argv.empty() ? nullptr : entrypoint_argv.data();
        return properties;
    }

    class MultiViewDesktopPlugin;

    MultiViewDesktopPlugin *g_plugin_instance = nullptr;
    FlutterDesktopEngineRef g_engine_ref = nullptr;

    class MultiViewDesktopPlugin : public flutter::Plugin {
    public:
        static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

        explicit MultiViewDesktopPlugin(flutter::PluginRegistrarWindows *registrar);

        ~MultiViewDesktopPlugin() override;

        std::optional <LRESULT> HandleWindowProc(HWND hwnd,
                                                 UINT message,
                                                 WPARAM wparam,
                                                 LPARAM lparam);

    private:
        flutter::PluginRegistrarWindows *registrar_;
        int window_proc_id_ = -1;
        std::unique_ptr <flutter::MethodChannel<flutter::EncodableValue>>
                screen_retriever_channel_;

        void HandleMethodCall(
                const flutter::MethodCall <flutter::EncodableValue> &method_call,
                std::unique_ptr <flutter::MethodResult<flutter::EncodableValue>> result);

        void HandleViewMethod(
                const flutter::MethodCall <flutter::EncodableValue> &method_call,
                MultiViewDesktop *window,
                int64_t view_id,
                std::unique_ptr <flutter::MethodResult<flutter::EncodableValue>> result);

        void HandleScreenRetrieverMethodCall(
                const flutter::MethodCall <flutter::EncodableValue> &method_call,
                std::unique_ptr <flutter::MethodResult<flutter::EncodableValue>> result);

        void EmitEvent(const std::string &event_name, int64_t view_id);
    };

    void MultiViewDesktopPlugin::RegisterWithRegistrar(
            flutter::PluginRegistrarWindows *registrar) {
        auto plugin = std::make_unique<MultiViewDesktopPlugin>(registrar);
        registrar->AddPlugin(std::move(plugin));
    }

    MultiViewDesktopPlugin::MultiViewDesktopPlugin(
            flutter::PluginRegistrarWindows *registrar)
            : registrar_(registrar) {
        g_plugin_instance = this;
        auto &impl = MultiViewDesktop::Instance();
        impl.SetupChannel(registrar->messenger());
        impl.channel()->SetMethodCallHandler(
                [this](const auto &call, auto result) {
                    HandleMethodCall(call, std::move(result));
                });

        auto screen_channel =
                std::make_unique < flutter::MethodChannel < flutter::EncodableValue >> (
                        registrar->messenger(), "multiview_desktop/screen_retriever",
                                &flutter::StandardMethodCodec::GetInstance());
        screen_channel->SetMethodCallHandler(
                [this](const auto &call, auto result) {
                    HandleScreenRetrieverMethodCall(call, std::move(result));
                });
        screen_retriever_channel_ = std::move(screen_channel);

        window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
                [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
                    return HandleWindowProc(hwnd, message, wparam, lparam);
                });
    }

    MultiViewDesktopPlugin::~MultiViewDesktopPlugin() {
        registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
        if (g_plugin_instance == this) {
            g_plugin_instance = nullptr;
        }
    }

    void MultiViewDesktopPlugin::EmitEvent(const std::string &event_name,
                                           int64_t view_id) {
        MultiViewDesktop::Instance().EmitEvent(event_name, view_id);
    }

    std::optional <LRESULT> MultiViewDesktopPlugin::HandleWindowProc(
            HWND hwnd,
            UINT message,
            WPARAM wparam,
            LPARAM lparam) {
        if (MvdWindowsHandleTaskbarMenuMessage(message, wparam, lparam)) {
            return 0;
        }

        auto &impl = MultiViewDesktop::Instance();
        MultiViewDesktop *window = impl.FindByHwnd(hwnd);
        if (!window) {
            return std::nullopt;
        }

        const int64_t view_id = window->view_id;
        std::optional <LRESULT> result = std::nullopt;

        if (message == WM_DPICHANGED) {
            window->pixel_ratio_ = static_cast<float>(LOWORD(wparam)) / USER_DEFAULT_SCREEN_DPI;
            window->ForceChildRefresh();
        }

        if (wparam && message == WM_NCCALCSIZE) {
            if (window->IsFullScreen() && window->title_bar_style_ != "normal") {
                if (window->is_frameless_) {
                    AdjustNCCalcSize(hwnd, reinterpret_cast<NCCALCSIZE_PARAMS *>(lparam));
                }
                return 0;
            }
            if (window->is_frameless_) {
                if (window->IsMaximized()) {
                    AdjustNCCalcSize(hwnd, reinterpret_cast<NCCALCSIZE_PARAMS *>(lparam));
                }
                return 0;
            }
            if (window->title_bar_style_ == "hidden") {
                if (window->IsMaximized()) {
                    AdjustNCCalcSize(hwnd, reinterpret_cast<NCCALCSIZE_PARAMS *>(lparam));
                } else {
                    NCCALCSIZE_PARAMS *sz = reinterpret_cast<NCCALCSIZE_PARAMS *>(lparam);
                    sz->rgrc[0].top += IsWindows11OrGreater() ? 0 : 1;
                    sz->rgrc[0].right -= 8;
                    sz->rgrc[0].bottom -= 8;
                    sz->rgrc[0].left -= -8;
                }
                return 0;
            }
        } else if (message == WM_NCHITTEST) {
            if (!window->is_resizable_) {
                return HTNOWHERE;
            }
        } else if (message == WM_GETMINMAXINFO) {
            MINMAXINFO *info = reinterpret_cast<MINMAXINFO *>(lparam);
            if (window->minimum_size_.x != 0) {
                info->ptMinTrackSize.x = static_cast<LONG>(
                        window->minimum_size_.x * window->pixel_ratio_);
            }
            if (window->minimum_size_.y != 0) {
                info->ptMinTrackSize.y = static_cast<LONG>(
                        window->minimum_size_.y * window->pixel_ratio_);
            }
            if (window->maximum_size_.x != -1) {
                info->ptMaxTrackSize.x = static_cast<LONG>(
                        window->maximum_size_.x * window->pixel_ratio_);
            }
            if (window->maximum_size_.y != -1) {
                info->ptMaxTrackSize.y = static_cast<LONG>(
                        window->maximum_size_.y * window->pixel_ratio_);
            }
            result = 0;
        } else if (message == WM_NCACTIVATE) {
            EmitEvent(wparam != 0 ? "focus" : "blur", view_id);
            if (window->title_bar_style_ == "hidden" || window->is_frameless_) {
                return 1;
            }
        } else if (message == WM_EXITSIZEMOVE) {
            if (window->is_resizing_) {
                EmitEvent("resized", view_id);
                window->is_resizing_ = false;
            }
            if (window->is_moving_) {
                EmitEvent("moved", view_id);
                window->is_moving_ = false;
            }
            return false;
        } else if (message == WM_MOVING) {
            window->is_moving_ = true;
            EmitEvent("move", view_id);
            return false;
        } else if (message == WM_SIZING) {
            window->is_resizing_ = true;
            EmitEvent("resize", view_id);
            if (window->aspect_ratio_ > 0) {
                RECT *rect = reinterpret_cast<LPRECT>(lparam);
                const double aspect_ratio = window->aspect_ratio_;
                int new_width = static_cast<int>(rect->right - rect->left);
                int new_height = static_cast<int>(rect->bottom - rect->top);
                const bool horizontal =
                        wparam == WMSZ_LEFT || wparam == WMSZ_RIGHT || wparam == WMSZ_TOPLEFT ||
                        wparam == WMSZ_BOTTOMLEFT;
                if (horizontal) {
                    new_height = static_cast<int>(new_width / aspect_ratio);
                } else {
                    new_width = static_cast<int>(new_height * aspect_ratio);
                }
                switch (wparam) {
                    case WMSZ_RIGHT:
                    case WMSZ_BOTTOM:
                        rect->right = new_width + rect->left;
                        rect->bottom = rect->top + new_height;
                        break;
                    case WMSZ_TOP:
                        rect->right = new_width + rect->left;
                        rect->top = rect->bottom - new_height;
                        break;
                    case WMSZ_LEFT:
                    case WMSZ_TOPLEFT:
                        rect->left = rect->right - new_width;
                        rect->top = rect->bottom - new_height;
                        break;
                    case WMSZ_TOPRIGHT:
                        rect->right = rect->left + new_width;
                        rect->top = rect->bottom - new_height;
                        break;
                    case WMSZ_BOTTOMLEFT:
                        rect->left = rect->right - new_width;
                        rect->bottom = rect->top + new_height;
                        break;
                    case WMSZ_BOTTOMRIGHT:
                        rect->right = rect->left + new_width;
                        rect->bottom = rect->top + new_height;
                        break;
                    default:
                        break;
                }
            }
        } else if (message == WM_SIZE) {
//    multi_view_desktop::MultiViewDesktop::ResizeFlutterContent(window);
            if (window->IsFullScreen() && wparam == SIZE_MAXIMIZED &&
                window->last_state != STATE_FULLSCREEN_ENTERED) {
                EmitEvent("enter-full-screen", view_id);
                window->last_state = STATE_FULLSCREEN_ENTERED;
            } else if (!window->IsFullScreen() && wparam == SIZE_RESTORED &&
                       window->last_state == STATE_FULLSCREEN_ENTERED) {
                window->ForceChildRefresh();
                EmitEvent("leave-full-screen", view_id);
                window->last_state = STATE_NORMAL;
            } else if (window->last_state != STATE_FULLSCREEN_ENTERED) {
                if (wparam == SIZE_MAXIMIZED) {
                    EmitEvent("maximize", view_id);
                    window->last_state = STATE_MAXIMIZED;
                } else if (wparam == SIZE_MINIMIZED) {
                    EmitEvent("minimize", view_id);
                    window->last_state = STATE_MINIMIZED;
                    return 0;
                } else if (wparam == SIZE_RESTORED) {
                    if (window->last_state == STATE_MAXIMIZED) {
                        EmitEvent("unmaximize", view_id);
                        window->last_state = STATE_NORMAL;
                    } else if (window->last_state == STATE_MINIMIZED) {
                        EmitEvent("restore", view_id);
                        window->last_state = STATE_NORMAL;
                    }
                }
            }
        } else if (message == WM_CLOSE) {
            if (!window->is_pre_confirm_) {
                EmitEvent("preconfirm-close", view_id);
                return 0;
            }
            if (window->IsPreventClose()) {
                EmitEvent("close", view_id);
                return 0;
            }
            if (!window->IsConfirmClose()) {
                EmitEvent("confirm-close", view_id);
                return 0;
            }
            impl.DestroyEntry(view_id);
            if (impl.windows_.empty() &&
                MultiViewDesktop::terminate_after_last_window_closed_) {
                PostQuitMessage(0);
            }
            return 0;
        } else if (message == WM_SHOWWINDOW) {
            EmitEvent(wparam == TRUE ? "show" : "hide", view_id);
        }

        return result;
    }

    void MultiViewDesktopPlugin::HandleMethodCall(
            const flutter::MethodCall <flutter::EncodableValue> &method_call,
            std::unique_ptr <flutter::MethodResult<flutter::EncodableValue>> result) {
        auto &impl = MultiViewDesktop::Instance();
        const std::string &method = method_call.method_name();
        const flutter::EncodableMap args =
                method_call.arguments() && !method_call.arguments()->IsNull()
                ? std::get<flutter::EncodableMap>(*method_call.arguments())
                : flutter::EncodableMap();

        if (method == "checkExistViewId") {
            const int64_t view_id = MultiViewDesktop::Int64FromMap(args, "viewId");
            result->Success(flutter::EncodableValue(impl.FindByViewId(view_id) != nullptr));
            return;
        }
        if (method == "createWindow") {
            impl.CreateSecondaryWindow(args);
            result->Success();
            return;
        }
        if (method == "createModalDialog") {
            impl.CreateModalDialogWindow(args);
            result->Success();
            return;
        }
        if (method == "setTerminateAfterLastWindowClosed") {
            MultiViewDesktop::terminate_after_last_window_closed_ =
                    MultiViewDesktop::BoolFromMap(args, "terminateAfterLastWindowClosed", true);
            result->Success();
            return;
        }
        if (method == "setAnchorViewId") {
            MultiViewDesktop::main_view_id_ =
                    MultiViewDesktop::Int64FromMap(args, "viewId");
            result->Success();
            return;
        }
        if (method == "isHideAppFromTaskbar") {
            if (impl.windows_.empty()) {
                result->Success(flutter::EncodableValue(true));
                return;
            }
            bool all_hidden = true;
            for (const auto &entry: impl.windows_) {
                if (!entry.second->IsSkipTaskbar()) {
                    all_hidden = false;
                    break;
                }
            }
            result->Success(flutter::EncodableValue(all_hidden));
            return;
        }
        if (method == "isHideAppTabFromTaskbar") {
            const int64_t view_id = MultiViewDesktop::Int64FromMap(args, "viewId");
            MultiViewDesktop *entry = impl.FindByViewId(view_id);
            result->Success(flutter::EncodableValue(
                    entry != nullptr && entry->IsSkipTaskbar()));
            return;
        }
        if (method == "setProgressBar") {
            MultiViewDesktop* window = impl.FindByViewId(impl.main_view_id());
            if (window != nullptr) {
                const double progress =
                        MultiViewDesktop::DoubleFromMap(args, "progress", -1);
                window->SetProgressBar(progress);
            }
            result->Success();
            return;
        }
        if (method == "setTaskbarMenu") {
            const flutter::EncodableValue* items_value = nullptr;
            const auto items_it = args.find(flutter::EncodableValue("items"));
            if (items_it != args.end()) {
                items_value = &items_it->second;
            }
            MvdWindowsSetTaskbarMenu(items_value);
            MvdWindowsFlushPendingTaskbarMenuSelection();
            result->Success();
            return;
        }

        const int64_t view_id = MultiViewDesktop::Int64FromMap(args, "viewId");
        MultiViewDesktop *window = impl.FindByViewId(view_id);
        if (!window) {
            result->Error("NO_WINDOW", "No window for viewId");
            return;
        }
        HandleViewMethod(method_call, window, view_id, std::move(result));
    }

    void MultiViewDesktopPlugin::HandleViewMethod(
            const flutter::MethodCall <flutter::EncodableValue> &method_call,
            MultiViewDesktop *window,
            int64_t view_id,
            std::unique_ptr <flutter::MethodResult<flutter::EncodableValue>> result) {
        const std::string &method = method_call.method_name();
        const flutter::EncodableMap args =
                method_call.arguments() && !method_call.arguments()->IsNull()
                ? std::get<flutter::EncodableMap>(*method_call.arguments())
                : flutter::EncodableMap();

        if (method == "closeWindow") {
            window->Close();
            result->Success();
        } else if (method == "destroyWindow") {
            auto &impl = MultiViewDesktop::Instance();
            impl.DestroyEntry(view_id);

            result->Success();
        } else if (method == "isPreventClose") {
            result->Success(flutter::EncodableValue(window->IsPreventClose()));
        } else if (method == "hideAppFromTaskbar") {
            window->SetSkipTaskbar(args);
            result->Success();
        } else if (method == "setPreventClose") {
            window->SetPreventClose(args);
            result->Success();
        } else if (method == "confirmClose") {
            window->SetConfirmClose(args);
            result->Success();
        } else if (method == "preConfirmClose") {
            window->SetPreConfirmClose(args);
            result->Success();
        } else if (method == "setTitle") {
            window->SetTitle(args);
            result->Success();
        } else if (method == "getTitle") {
            result->Success(flutter::EncodableValue(window->GetTitle()));
        } else if (method == "getTitleBarStyle") {
            result->Success(flutter::EncodableValue(window->GetTitleBarStyle()));
        } else if (method == "setTitleBarStyle") {
            window->SetTitleBarStyle(args);
            result->Success();
        } else if (method == "setAsFrameless") {
            window->SetAsFrameless();
            result->Success();
        } else if (method == "show") {
            window->Show();
            result->Success();
        } else if (method == "hide") {
            window->Hide();
            result->Success();
        } else if (method == "isVisible") {
            result->Success(flutter::EncodableValue(window->IsVisible()));
        } else if (method == "focus") {
            window->Focus();
            result->Success();
        } else if (method == "blur") {
            window->Blur();
            result->Success();
        } else if (method == "isFocused") {
            result->Success(flutter::EncodableValue(window->IsFocused()));
        } else if (method == "isOnActiveSpace") {
            result->Success(flutter::EncodableValue(true));
        } else if (method == "maximize") {
            window->Maximize(args);
            result->Success();
        } else if (method == "unmaximize") {
            window->Unmaximize();
            result->Success();
        } else if (method == "isMaximized") {
            result->Success(flutter::EncodableValue(window->IsMaximized()));
        } else if (method == "minimize") {
            window->Minimize();
            result->Success();
        } else if (method == "restore") {
            window->Restore();
            result->Success();
        } else if (method == "isMinimized") {
            result->Success(flutter::EncodableValue(window->IsMinimized()));
        } else if (method == "isFullScreen") {
            result->Success(flutter::EncodableValue(window->IsFullScreen()));
        } else if (method == "setFullScreen") {
            window->SetFullScreen(args);
            result->Success();
        } else if (method == "getBounds") {
            result->Success(flutter::EncodableValue(window->GetBounds(args)));
        } else if (method == "setSize") {
            window->SetSize(args);
            result->Success();
        } else if (method == "setPosition") {
            window->SetPosition(args);
            result->Success();
        } else if (method == "center") {
            window->Center();
            result->Success();
        } else if (method == "setMinimumSize") {
            window->SetMinimumSize(args);
            result->Success();
        } else if (method == "setMaximumSize") {
            window->SetMaximumSize(args);
            result->Success();
        } else if (method == "setAspectRatio") {
            window->SetAspectRatio(args);
            result->Success();
        } else if (method == "isResizable") {
            result->Success(flutter::EncodableValue(window->IsResizable()));
        } else if (method == "setResizable") {
            window->SetResizable(args);
            result->Success();
        } else if (method == "isMovable") {
            result->Success(flutter::EncodableValue(window->IsMovable()));
        } else if (method == "setMovable") {
            window->SetMovable(args);
            result->Success();
        } else if (method == "isMinimizable") {
            result->Success(flutter::EncodableValue(window->IsMinimizable()));
        } else if (method == "setMinimizable") {
            window->SetMinimizable(args);
            result->Success();
        } else if (method == "isMaximizable") {
            result->Success(flutter::EncodableValue(window->IsMaximizable()));
        } else if (method == "setMaximizable") {
            window->SetMaximizable(args);
            result->Success();
        } else if (method == "isClosable") {
            result->Success(flutter::EncodableValue(window->IsClosable()));
        } else if (method == "setClosable") {
            window->SetClosable(args);
            result->Success();
        } else if (method == "isAlwaysOnTop") {
            result->Success(flutter::EncodableValue(window->IsAlwaysOnTop()));
        } else if (method == "setAlwaysOnTop") {
            window->SetAlwaysOnTop(args);
            result->Success();
        } else if (method == "hasShadow") {
            result->Success(flutter::EncodableValue(window->HasShadow()));
        } else if (method == "setHasShadow") {
            window->SetHasShadow(args);
            result->Success();
        } else if (method == "getOpacity") {
            result->Success(flutter::EncodableValue(window->GetOpacity()));
        } else if (method == "setOpacity") {
            window->SetOpacity(args);
            result->Success();
        } else if (method == "setBrightness") {
            window->SetBrightness(args);
            result->Success();
        } else if (method == "setBackgroundColor") {
            window->SetBackgroundColor(args);
            result->Success();
        } else if (method == "setIgnoreMouseEvents") {
            window->SetIgnoreMouseEvents(args);
            result->Success();
        } else if (method == "isIgnoreMouseEvents") {
            result->Success(flutter::EncodableValue(window->IsIgnoreMouseEvents()));
        } else if (method == "startDragging") {
            window->StartDragging();
            result->Success();
        } else if (method == "startResizing") {
            window->StartResizing(args);
            result->Success();
        } else if (method == "popUpWindowMenu") {
            window->PopUpWindowMenu(args);
            result->Success();
        } else if (method == "setBadgeLabel" || method == "hideFromCollection" ||
                   method == "isHideFromCollection" || method == "isVisibleOnAllWorkspaces" ||
                   method == "setVisibleOnAllWorkspaces") {
            result->Success();
        } else {
            result->NotImplemented();
        }
    }

    struct MwmMonitorData {
        RECT geometry;
        RECT workarea;
        HMONITOR handle;
        int index;
    };

    static BOOL CALLBACK
    MwmEnumMonitorsProc(HMONITOR
    monitor, HDC, LPRECT,
    LPARAM lparam
    ) {
    auto *list = reinterpret_cast<std::vector <MwmMonitorData> *>(lparam);
    MONITORINFO info;
    info.
    cbSize = sizeof(MONITORINFO);
    if (
    GetMonitorInfo(monitor, &info
    )) {
    MwmMonitorData data;
    data.
    handle = monitor;
    data.
    geometry = info.rcMonitor;
    data.
    workarea = info.rcWork;
    data.
    index = static_cast<int>(list->size());
    list->
    push_back(data);
}
return
TRUE;
}

static UINT MwmGetDpiForMonitor(HMONITOR monitor) {
    using GetDpiForMonitorFn =
    HRESULT(WINAPI * )(HMONITOR, int, UINT * , UINT * );
    static GetDpiForMonitorFn fn = []() -> GetDpiForMonitorFn {
        HMODULE module = LoadLibraryW(L"shcore.dll");
        return module ? reinterpret_cast<GetDpiForMonitorFn>(
                GetProcAddress(module, "GetDpiForMonitor"))
                      : nullptr;
    }();
    UINT dpi_x = 96;
    UINT dpi_y = 96;
    if (fn) {
        fn(monitor, 0, &dpi_x, &dpi_y);
    }
    return dpi_x;
}

static std::string MwmWcharToUtf8(const wchar_t *wstr) {
    const int len =
            WideCharToMultiByte(CP_UTF8, 0, wstr, -1, nullptr, 0, nullptr, nullptr);
    if (len <= 0) {
        return {};
    }
    std::string buf(static_cast<size_t>(len - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wstr, -1, buf.data(), len, nullptr, nullptr);
    return buf;
}

static flutter::EncodableMap MwmMonitorToMap(const MwmMonitorData &data) {
    constexpr double k_base_dpi = 96.0;
    const double scale = MwmGetDpiForMonitor(data.handle) / k_base_dpi;
    const double vis_x = std::round(data.workarea.left / scale);
    const double vis_y = std::round(data.workarea.top / scale);
    const double vis_w =
            std::round((data.workarea.right - data.workarea.left) / scale);
    const double vis_h =
            std::round((data.workarea.bottom - data.workarea.top) / scale);
    const double w = std::round(data.geometry.right / scale - vis_x);
    const double h = std::round(data.geometry.bottom / scale - vis_y);

    std::string name;
    std::string id;
    MONITORINFOEX info_ex;
    info_ex.cbSize = sizeof(MONITORINFOEX);
    if (GetMonitorInfo(data.handle, &info_ex)) {
        name = MwmWcharToUtf8(info_ex.szDevice);
        DISPLAY_DEVICE display_device;
        display_device.cb = sizeof(DISPLAY_DEVICE);
        int idx = 0;
        while (EnumDisplayDevices(info_ex.szDevice, idx, &display_device, 0)) {
            if ((display_device.StateFlags & DISPLAY_DEVICE_ACTIVE) &&
                (display_device.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP)) {
                const std::wstring dev_name(display_device.DeviceName);
                if (dev_name.find(info_ex.szDevice) == 0) {
                    id = MwmWcharToUtf8(display_device.DeviceID);
                    break;
                }
            }
            ++idx;
        }
    }

    return flutter::EncodableMap{
            {flutter::EncodableValue("id"),          flutter::EncodableValue(id)},
            {flutter::EncodableValue("name"),        flutter::EncodableValue(name)},
            {flutter::EncodableValue("size"),
                                                     flutter::EncodableValue(flutter::EncodableMap{
                                                             {flutter::EncodableValue(
                                                                     "width"),  flutter::EncodableValue(
                                                                     w)},
                                                             {flutter::EncodableValue(
                                                                     "height"), flutter::EncodableValue(
                                                                     h)},
                                                     })},
            {flutter::EncodableValue("visiblePosition"),
                                                     flutter::EncodableValue(flutter::EncodableMap{
                                                             {flutter::EncodableValue(
                                                                     "dx"), flutter::EncodableValue(
                                                                     vis_x)},
                                                             {flutter::EncodableValue(
                                                                     "dy"), flutter::EncodableValue(
                                                                     vis_y)},
                                                     })},
            {flutter::EncodableValue("visibleSize"),
                                                     flutter::EncodableValue(flutter::EncodableMap{
                                                             {flutter::EncodableValue(
                                                                     "width"),  flutter::EncodableValue(
                                                                     vis_w)},
                                                             {flutter::EncodableValue(
                                                                     "height"), flutter::EncodableValue(
                                                                     vis_h)},
                                                     })},
            {flutter::EncodableValue("scaleFactor"), flutter::EncodableValue(scale)},
    };
}

void MultiViewDesktopPlugin::HandleScreenRetrieverMethodCall(
        const flutter::MethodCall <flutter::EncodableValue> &method_call,
        std::unique_ptr <flutter::MethodResult<flutter::EncodableValue>> result) {
    const std::string &method = method_call.method_name();
    double device_pixel_ratio = 1.0;
    if (method_call.arguments() && !method_call.arguments()->IsNull()) {
        if (const auto *args = std::get_if<flutter::EncodableMap>(method_call.arguments())) {
            const auto it = args->find(flutter::EncodableValue("devicePixelRatio"));
            if (it != args->end()) {
                if (const auto *value = std::get_if<double>(&it->second)) {
                    device_pixel_ratio = *value;
                }
            }
        }
    }

    if (method == "getCursorScreenPoint") {
        POINT point;
        GetCursorPos(&point);
        result->Success(flutter::EncodableValue(flutter::EncodableMap{
                {flutter::EncodableValue("dx"),
                        flutter::EncodableValue(point.x / device_pixel_ratio)},
                {flutter::EncodableValue("dy"),
                        flutter::EncodableValue(point.y / device_pixel_ratio)},
        }));
    } else if (method == "getPrimaryDisplay") {
        const HMONITOR primary =
                MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
        MONITORINFO info;
        info.cbSize = sizeof(MONITORINFO);
        if (GetMonitorInfo(primary, &info)) {
            MwmMonitorData data;
            data.handle = primary;
            data.geometry = info.rcMonitor;
            data.workarea = info.rcWork;
            result->Success(flutter::EncodableValue(MwmMonitorToMap(data)));
        } else {
            result->Error("NO_MONITOR", "No monitors found");
        }
    } else if (method == "getAllDisplays") {
        std::vector <MwmMonitorData> monitors;
        EnumDisplayMonitors(nullptr, nullptr, MwmEnumMonitorsProc,
                            reinterpret_cast<LPARAM>(&monitors));
        flutter::EncodableList list;
        for (const auto &monitor: monitors) {
            list.push_back(flutter::EncodableValue(MwmMonitorToMap(monitor)));
        }
        result->Success(flutter::EncodableValue(flutter::EncodableMap{
                {flutter::EncodableValue("displays"), flutter::EncodableValue(list)},
        }));
    } else {
        result->NotImplemented();
    }
}


std::optional <LRESULT> HandleWindowProcForHwnd(HWND hwnd,
                                                UINT message,
                                                WPARAM wparam,
                                                LPARAM lparam) {
    if (g_plugin_instance == nullptr) {
        return std::nullopt;
    }
    return g_plugin_instance->HandleWindowProc(hwnd, message, wparam, lparam);
}

}  // namespace multi_view_desktop

void MultiViewDesktopPluginRegisterWithRegistrar(
        FlutterDesktopPluginRegistrarRef registrar) {
    multi_view_desktop::MultiViewDesktopPlugin::RegisterWithRegistrar(
            flutter::PluginRegistrarManager::GetInstance()
                    ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

void MultiViewDesktopPrepareEngine(const flutter::DartProject &project,
                                   HWND main_host_window) {
    multi_view_desktop::MvdWindowsInitializeShellIntegration();
    if (!multi_view_desktop::g_engine_ref) {
        const FlutterDesktopEngineProperties properties =
                multi_view_desktop::BuildEngineProperties(project);
        multi_view_desktop::g_engine_ref = FlutterDesktopEngineCreate(&properties);
        multi_view_desktop::MultiViewDesktop::Instance().SetEngine(
                multi_view_desktop::g_engine_ref);
        FlutterDesktopEngineRun(multi_view_desktop::g_engine_ref, nullptr);
    }
    multi_view_desktop::MultiViewDesktop::Instance().SetMainHostWindow(
            main_host_window);
    multi_view_desktop::MvdWindowsApplyAppUserModelIdToWindow(main_host_window);
}

FlutterDesktopEngineRef MultiViewDesktopGetEngineRef() {
    return multi_view_desktop::g_engine_ref;
}

int64_t MultiViewDesktopGetMainViewId() {
    return multi_view_desktop::MultiViewDesktop::Instance().main_view_id();
}

HWND MultiViewDesktopGetFlutterHwnd(int64_t view_id) {
    auto *window =
            multi_view_desktop::MultiViewDesktop::Instance().FindByViewId(view_id);
    if (window == nullptr || window->controller == nullptr) {
        return nullptr;
    }
    FlutterDesktopViewRef view =
            FlutterDesktopViewControllerGetView(window->controller);
    return view == nullptr ? nullptr : FlutterDesktopViewGetHWND(view);
}

void MultiViewDesktopCreateMainView(HWND host_window, int width, int height) {
    auto &impl = multi_view_desktop::MultiViewDesktop::Instance();
    FlutterDesktopViewControllerProperties properties = {width, height};
    FlutterDesktopViewControllerRef controller =
            FlutterDesktopEngineCreateViewController(impl.engine(), &properties);
    if (!controller) {
        return;
    }
    const int64_t view_id =
            static_cast<int64_t>(FlutterDesktopViewControllerGetViewId(controller));
    FlutterDesktopViewRef view = FlutterDesktopViewControllerGetView(controller);
    HWND flutter_hwnd = FlutterDesktopViewGetHWND(view);
    if (host_window) {
        SetParent(flutter_hwnd, host_window);
        RECT rect{};
        GetClientRect(host_window, &rect);
        SetWindowPos(flutter_hwnd, nullptr, 0, 0, rect.right - rect.left,
                     rect.bottom - rect.top,
                     SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
        impl.RegisterMain(host_window, view_id, controller);
        if (auto *main_window = impl.FindByViewId(view_id)) {
            multi_view_desktop::MultiViewDesktop::ResizeFlutterContent(main_window);
        }
    } else {
        impl.RegisterMain(flutter_hwnd, view_id, controller);
    }

    MultiViewDesktopPluginRegisterWithRegistrar(
            FlutterDesktopEngineGetPluginRegistrar(impl.engine(),
                                                   "MultiViewDesktopPlugin"));
}

bool MultiViewDesktopHandleWindowProc(HWND hwnd,
                                      UINT message,
                                      WPARAM wparam,
                                      LPARAM lparam,
                                      LRESULT *result) {
    const auto optional = multi_view_desktop::HandleWindowProcForHwnd(
            hwnd, message, wparam, lparam);
    if (optional.has_value()) {
        *result = *optional;
        return true;
    }
    return false;
}

bool MultiViewDesktopTryForwardTaskbarMenuActivation() {
    return multi_view_desktop::MvdWindowsTryForwardTaskbarMenuActivation();
}

void MultiViewDesktopInitializeShellIntegration() {
    multi_view_desktop::MvdWindowsInitializeShellIntegration();
}
