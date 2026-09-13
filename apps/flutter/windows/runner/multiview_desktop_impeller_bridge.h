#pragma once

#include <flutter_windows.h>

FlutterDesktopEngineRef PomodoistFlutterDesktopEngineCreate(
    const FlutterDesktopEngineProperties* properties);

#define FlutterDesktopEngineCreate PomodoistFlutterDesktopEngineCreate
