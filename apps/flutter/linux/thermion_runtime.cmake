# Thermion 0.5.0 searches upward from CMAKE_BINARY_DIR. This repository keeps
# build/ outside the application, so use the application's package map explicitly.
find_package(Python3 REQUIRED COMPONENTS Interpreter)
execute_process(
  COMMAND "${Python3_EXECUTABLE}"
    "${CMAKE_CURRENT_SOURCE_DIR}/resolve_thermion.py"
    "${CMAKE_CURRENT_SOURCE_DIR}/../.dart_tool/package_config.json"
  RESULT_VARIABLE POMODOIST_THERMION_RESOLVE_RESULT
  OUTPUT_VARIABLE POMODOIST_THERMION_ROOT
  ERROR_VARIABLE POMODOIST_THERMION_RESOLVE_ERROR
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(NOT POMODOIST_THERMION_RESOLVE_RESULT EQUAL 0)
  message(FATAL_ERROR "${POMODOIST_THERMION_RESOLVE_ERROR}")
endif()
target_include_directories(thermion_flutter_plugin BEFORE PRIVATE
  "${POMODOIST_THERMION_ROOT}/native/include"
  "${POMODOIST_THERMION_ROOT}/native/include/filament"
  "${POMODOIST_THERMION_ROOT}/native/include/filament/release"
  "${POMODOIST_THERMION_ROOT}/native/include/vulkan/linux"
  "${POMODOIST_THERMION_ROOT}/native/include/opengl/linux"
)
target_link_directories(thermion_flutter_plugin BEFORE PRIVATE
  "${PROJECT_BUILD_DIR}native_assets/linux")
set_property(TARGET thermion_flutter_plugin APPEND PROPERTY BUILD_RPATH
  "${PROJECT_BUILD_DIR}native_assets/linux")

# Keep the dependency cache immutable. Generate the reviewed 0.5.0 source
# override in this build tree and replace only its plugin translation unit.
get_target_property(POMODOIST_THERMION_PLUGIN_DIR thermion_flutter_plugin SOURCE_DIR)
set(POMODOIST_THERMION_PLUGIN_SOURCE
  "${POMODOIST_THERMION_PLUGIN_DIR}/thermion_flutter_plugin.cc")
set(POMODOIST_THERMION_PATCHED_SOURCE
  "${CMAKE_CURRENT_BINARY_DIR}/thermion/thermion_flutter_plugin.cc")
execute_process(
  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/thermion/prepare_source.py"
    "${POMODOIST_THERMION_PLUGIN_SOURCE}" "${POMODOIST_THERMION_PATCHED_SOURCE}"
  RESULT_VARIABLE POMODOIST_THERMION_PATCH_RESULT
  ERROR_VARIABLE POMODOIST_THERMION_PATCH_ERROR
)
if(NOT POMODOIST_THERMION_PATCH_RESULT EQUAL 0)
  message(FATAL_ERROR "${POMODOIST_THERMION_PATCH_ERROR}")
endif()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  "${POMODOIST_THERMION_PLUGIN_SOURCE}"
  "${CMAKE_CURRENT_SOURCE_DIR}/thermion/prepare_source.py")
get_target_property(POMODOIST_THERMION_SOURCES thermion_flutter_plugin SOURCES)
set(POMODOIST_THERMION_LOCAL_SOURCES "")
foreach(POMODOIST_THERMION_SOURCE IN LISTS POMODOIST_THERMION_SOURCES)
  if(POMODOIST_THERMION_SOURCE STREQUAL "thermion_flutter_plugin.cc")
    list(APPEND POMODOIST_THERMION_LOCAL_SOURCES "${POMODOIST_THERMION_PATCHED_SOURCE}")
  elseif(IS_ABSOLUTE "${POMODOIST_THERMION_SOURCE}")
    list(APPEND POMODOIST_THERMION_LOCAL_SOURCES "${POMODOIST_THERMION_SOURCE}")
  else()
    list(APPEND POMODOIST_THERMION_LOCAL_SOURCES
      "${POMODOIST_THERMION_PLUGIN_DIR}/${POMODOIST_THERMION_SOURCE}")
  endif()
endforeach()
set_property(TARGET thermion_flutter_plugin PROPERTY SOURCES "${POMODOIST_THERMION_LOCAL_SOURCES}")
target_include_directories(thermion_flutter_plugin BEFORE PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}" "${POMODOIST_THERMION_PLUGIN_DIR}")
pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)
target_link_libraries(thermion_flutter_plugin PRIVATE PkgConfig::EPOXY PkgConfig::X11)
