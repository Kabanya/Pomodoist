#ifndef FLUTTER_PLUGIN_MULTI_VIEW_DESKTOP_PLUGIN_H_
#define FLUTTER_PLUGIN_MULTI_VIEW_DESKTOP_PLUGIN_H_

#include <flutter/dart_project.h>
#include <flutter_windows.h>
#include <windows.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void MultiViewDesktopPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}

namespace flutter {
class DartProject;
}  // namespace flutter

// Runner integration (mirrors macOS MultiviewDesktopPlugin.prepareEngine).
FLUTTER_PLUGIN_EXPORT void MultiViewDesktopPrepareEngine(
    const flutter::DartProject& project,
    HWND main_host_window);

FLUTTER_PLUGIN_EXPORT FlutterDesktopEngineRef MultiViewDesktopGetEngineRef();

FLUTTER_PLUGIN_EXPORT void MultiViewDesktopCreateMainView(HWND host_window,
                                                          int width,
                                                          int height);

FLUTTER_PLUGIN_EXPORT int64_t MultiViewDesktopGetMainViewId();

FLUTTER_PLUGIN_EXPORT HWND MultiViewDesktopGetFlutterHwnd(int64_t view_id);

FLUTTER_PLUGIN_EXPORT bool MultiViewDesktopHandleWindowProc(
    HWND hwnd,
    UINT message,
    WPARAM wparam,
    LPARAM lparam,
    LRESULT* result);

// Must run before any UI or jump list updates (call from wWinMain after CoInitializeEx).
FLUTTER_PLUGIN_EXPORT void MultiViewDesktopInitializeShellIntegration();

// Returns true when a jump list activation was forwarded to another instance
// and this process should exit before creating the Flutter window.
FLUTTER_PLUGIN_EXPORT bool MultiViewDesktopTryForwardTaskbarMenuActivation();

#endif  // __cplusplus

#endif  // FLUTTER_PLUGIN_MULTI_VIEW_DESKTOP_PLUGIN_H_
