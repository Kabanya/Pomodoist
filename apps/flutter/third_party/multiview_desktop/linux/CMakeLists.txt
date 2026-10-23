cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "multiview_desktop")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "multiview_desktop_plugin")

pkg_check_modules(GTK_LAYER_SHELL REQUIRED IMPORTED_TARGET gtk-layer-shell-0>=0.6)
pkg_check_modules(WAYLAND_CLIENT REQUIRED IMPORTED_TARGET wayland-client>=1.20)
pkg_check_modules(MVD_EPOXY REQUIRED IMPORTED_TARGET epoxy)

add_library(${PLUGIN_NAME} SHARED
  "multiview_desktop_plugin.cc"
  "mvd_linux_taskbar_menu.cc"
  "mvd_linux_window.cc"
  "mvd_linux_runner.cc"
  "mvd_linux_pomo.cc"
  "mvd_linux_pomo_popup.cc"
  "mvd_linux_gnome.cc"
  "mvd_linux_pomo_drag.cc"
  "protocols/relative-pointer-unstable-v1-protocol.cc"
  "protocols/xdg-output-unstable-v1-protocol.cc"
)

apply_standard_settings(${PLUGIN_NAME})
# Existing plugin handlers use structured bindings; make the minimum explicit.
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_17)
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK PkgConfig::GTK_LAYER_SHELL PkgConfig::WAYLAND_CLIENT PkgConfig::MVD_EPOXY)

set(multiview_desktop_bundled_libraries
  ""
  PARENT_SCOPE
)
