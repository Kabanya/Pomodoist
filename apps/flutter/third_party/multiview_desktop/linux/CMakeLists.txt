cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "multiview_desktop")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "multiview_desktop_plugin")

add_library(${PLUGIN_NAME} SHARED
  "multiview_desktop_plugin.cc"
  "mvd_linux_taskbar_menu.cc"
  "mvd_linux_window.cc"
  "mvd_linux_runner.cc"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

set(multiview_desktop_bundled_libraries
  ""
  PARENT_SCOPE
)
