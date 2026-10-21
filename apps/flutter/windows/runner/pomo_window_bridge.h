#ifndef RUNNER_POMO_WINDOW_BRIDGE_H_
#define RUNNER_POMO_WINDOW_BRIDGE_H_
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/plugin_registrar_windows.h>
#include <multiview_desktop/multi_view_desktop_plugin.h>
#include <cmath>

inline std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreatePomoWindowChannel(FlutterDesktopEngineRef engine) {
  auto registrar = flutter::PluginRegistrarManager::GetInstance()
      ->GetRegistrar<flutter::PluginRegistrarWindows>(
          FlutterDesktopEngineGetPluginRegistrar(engine, "PomoWindowHost"));
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "pomodoist/pomo_window", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) { result->Error("arguments", "Missing Pomo arguments"); return; }
    auto find = [&](const char* key) -> const flutter::EncodableValue* {
      auto it = args->find(flutter::EncodableValue(key)); return it == args->end() ? nullptr : &it->second;
    };
    const auto* encoded = find("viewId");
    if (!encoded) { result->Error("arguments", "Missing Pomo view"); return; }
    int64_t id;
    if (auto p = std::get_if<int64_t>(encoded)) id = *p;
    else if (auto p = std::get_if<int32_t>(encoded)) id = *p;
    else { result->Error("arguments", "Invalid Pomo view"); return; }
    HWND child = MultiViewDesktopGetFlutterHwnd(id);
    HWND window = child ? GetAncestor(child, GA_ROOT) : nullptr;
    if (!window) { result->Error("window", "Pomo window unavailable"); return; }
    if (call.method_name() == "detach") { result->Success(); return; }
    if (call.method_name() == "bounds") {
      RECT rect{}; GetWindowRect(window, &rect);
      const double scale = static_cast<double>(GetDpiForWindow(window)) / 96.0;
      result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("x"), flutter::EncodableValue(rect.left/scale)},
        {flutter::EncodableValue("y"), flutter::EncodableValue(rect.top/scale)},
        {flutter::EncodableValue("width"), flutter::EncodableValue((rect.right-rect.left)/scale)},
        {flutter::EncodableValue("height"), flutter::EncodableValue((rect.bottom-rect.top)/scale)},
        {flutter::EncodableValue("scale"), flutter::EncodableValue(scale)}})); return;
    }
    if (call.method_name() == "move") {
      const auto *xv=find("x"), *yv=find("y"), *sv=find("scale");
      const auto *x=xv?std::get_if<double>(xv):nullptr;
      const auto *y=yv?std::get_if<double>(yv):nullptr;
      const auto *scale=sv?std::get_if<double>(sv):nullptr;
      if (!x || !y || !scale || !std::isfinite(*x) || !std::isfinite(*y) || *scale<=0) {
        result->Error("arguments", "Invalid display position"); return;
      }
      if (!SetWindowPos(window,nullptr,static_cast<int>(std::round(*x * *scale)),
            static_cast<int>(std::round(*y * *scale)),0,0,SWP_NOZORDER|SWP_NOACTIVATE|SWP_NOSIZE)) {
        result->Error("position", "Unable to move Pomo"); return;
      }
      result->Success(); return;
    }
    if (call.method_name() != "configure") { result->NotImplemented(); return; }
    const auto* regions_value = find("regions");
    const auto* regions = regions_value ? std::get_if<flutter::EncodableList>(regions_value) : nullptr;
    if (!regions) { result->Error("arguments", "Missing input regions"); return; }
    const double scale = static_cast<double>(GetDpiForWindow(window)) / 96.0;
    HRGN combined = CreateRectRgn(0, 0, 0, 0);
    for (const auto& entry : *regions) {
      const auto* region = std::get_if<flutter::EncodableMap>(&entry);
      if (!region) { DeleteObject(combined); result->Error("arguments", "Invalid region"); return; }
      auto number = [&](const char* key) -> double {
        auto it = region->find(flutter::EncodableValue(key));
        if (it == region->end()) return 0;
        if (auto p = std::get_if<double>(&it->second)) return *p;
        if (auto p = std::get_if<int32_t>(&it->second)) return *p;
        return 0;
      };
      int x = static_cast<int>(std::round(number("x")*scale));
      int y = static_cast<int>(std::round(number("y")*scale));
      int w = static_cast<int>(std::round(number("width")*scale));
      int h = static_cast<int>(std::round(number("height")*scale));
      auto rounded_it = region->find(flutter::EncodableValue("rounded"));
      bool rounded = rounded_it != region->end() && std::get_if<bool>(&rounded_it->second) && std::get<bool>(rounded_it->second);
      auto rectangle_it = region->find(flutter::EncodableValue("rectangle"));
      bool rectangle = rectangle_it != region->end() && std::get_if<bool>(&rectangle_it->second) && std::get<bool>(rectangle_it->second);
      HRGN part = rectangle ? CreateRectRgn(x,y,x+w+1,y+h+1)
          : rounded ? CreateRoundRectRgn(x,y,x+w+1,y+h+1,h,h) : CreateEllipticRgn(x,y,x+w+1,y+h+1);
      CombineRgn(combined,combined,part,RGN_OR); DeleteObject(part);
    }
    // This style belongs only to the companion; keep the main app in taskbar.
    SetWindowLongPtr(window, GWL_EXSTYLE, (GetWindowLongPtr(window,GWL_EXSTYLE)|WS_EX_TOOLWINDOW)&~WS_EX_APPWINDOW);
    if (!SetWindowRgn(window, combined, TRUE)) {
      DeleteObject(combined); result->Error("region", "Unable to apply Pomo input region"); return;
    }
    result->Success(); // Windows owns combined after successful SetWindowRgn.
  });
  return channel;
}
#endif
