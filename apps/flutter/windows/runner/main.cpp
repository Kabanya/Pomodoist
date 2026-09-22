#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shobjidl_core.h>
#include <windows.h>

#include "app_links/app_links_plugin_c_api.h"
#include "flavor_config.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

// Looks for a *same-flavor* window only. Production, staging and development
// can be installed and running side by side, so matching on the title alone
// would hand one build's deep link to whichever build happened to be running.
// The window class is what actually separates them; the title check keeps the
// match honest if the class is ever reused.
bool ForwardAppLinkToRunningInstance() {
  HWND window = ::FindWindow(POMODOIST_FLAVOR_WINDOW_CLASS_WIDE,
                             POMODOIST_FLAVOR_DISPLAY_NAME_WIDE);
  if (window == nullptr) {
    return false;
  }

  SendAppLink(window);
  ::ShowWindow(window, ::IsIconic(window) ? SW_RESTORE : SW_SHOW);
  ::SetWindowPos(window, HWND_TOP, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  ::SetForegroundWindow(window);
  return true;
}

} // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (ForwardAppLinkToRunningInstance()) {
    return EXIT_SUCCESS;
  }

  // Give the process its flavor's identity before any UI exists, so the taskbar
  // button and the notifications it raises are attributed to this flavor rather
  // than to the executable path.
  ::SetCurrentProcessExplicitAppUserModelID(
      POMODOIST_FLAVOR_APPLICATION_ID_WIDE);

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(POMODOIST_FLAVOR_DISPLAY_NAME_WIDE, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(false);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
