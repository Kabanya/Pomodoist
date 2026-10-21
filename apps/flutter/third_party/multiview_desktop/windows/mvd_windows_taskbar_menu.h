#ifndef MVD_WINDOWS_TASKBAR_MENU_H_
#define MVD_WINDOWS_TASKBAR_MENU_H_

#include <flutter/encodable_value.h>
#include <windows.h>

namespace multi_view_desktop {

// Must run before any UI or jump list updates (call from wWinMain after CoInitializeEx).
void MvdWindowsInitializeShellIntegration();

// If a jump list activation was forwarded to another instance, returns true and
// the caller should exit immediately.
bool MvdWindowsTryForwardTaskbarMenuActivation();

// Builds or clears the taskbar jump list from the Dart `setTaskbarMenu` payload.
void MvdWindowsSetTaskbarMenu(const flutter::EncodableValue* items_value);

// Emits a startup jump list selection once the method channel is ready.
void MvdWindowsFlushPendingTaskbarMenuSelection();

// Handles the registered window message for jump list activation.
bool MvdWindowsHandleTaskbarMenuMessage(UINT message, WPARAM wparam, LPARAM lparam);

// Assigns the same AppUserModelID used by the jump list to a top-level window.
void MvdWindowsApplyAppUserModelIdToWindow(HWND hwnd);

}  // namespace multi_view_desktop

#endif  // MVD_WINDOWS_TASKBAR_MENU_H_
