#include "multiview_desktop_impeller_bridge.h"

#undef FlutterDesktopEngineCreate

FlutterDesktopEngineRef PomodoistFlutterDesktopEngineCreate(
    const FlutterDesktopEngineProperties* properties) {
  auto configured = *properties;
  configured.impeller_switch = DisabledImpeller;
  return FlutterDesktopEngineCreate(&configured);
}
