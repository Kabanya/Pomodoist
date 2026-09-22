# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(pomodoist LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "pomodoist")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(
  -DUNICODE
  -D_UNICODE
  -D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS
)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# === Build flavor ===
#
# `flutter build windows --flavor <name>` makes the Flutter tool write
# `set(FLUTTER_APP_FLAVOR "<name>" PARENT_SCOPE)` into
# flutter/ephemeral/generated_config.cmake, which the flutter/CMakeLists.txt
# included just above. That PARENT_SCOPE write lands in this file's scope, so
# the variable exists only *after* that add_subdirectory call and has to be read
# here rather than in runner/CMakeLists.txt.
#
# A bare `flutter build windows`, a `flutter run`, and every build that predates
# the flavors carries no flavor at all, and production is what such a build
# compiles: the base Debug/Profile/Release configurations, the unflavored window
# class and the build/windows/x64 output directory. The repository tooling
# instead names the flavor on every build, production included, so its artifacts
# land in build/windows/x64/production. Both spellings produce the same
# application, and the installer and the updater address it by name.
if(NOT DEFINED FLUTTER_APP_FLAVOR OR FLUTTER_APP_FLAVOR STREQUAL "")
  set(FLUTTER_APP_FLAVOR "production")
endif()
string(TOLOWER "${FLUTTER_APP_FLAVOR}" FLUTTER_APP_FLAVOR)

# Per-flavor identity, mirroring lib/domain/models/app_flavor.dart. That file is
# the single source of truth; every value below has to match it cell for cell.
set(POMODOIST_FLAVOR_NAME "${FLUTTER_APP_FLAVOR}")
set(POMODOIST_FLAVOR_IS_DEVELOPMENT 0)
set(POMODOIST_FLAVOR_IS_STAGING 0)
set(POMODOIST_FLAVOR_IS_PRODUCTION 0)
set(POMODOIST_FLAVOR_DISPLAY_NAME "Pomodoist")
set(POMODOIST_FLAVOR_APPLICATION_ID "com.finchforge.pomodoist")
set(POMODOIST_FLAVOR_URL_SCHEME "pomodoist")
set(POMODOIST_FLAVOR_TOAST_GUID "8681f633-939c-46f5-84cc-18f295e4382c")
# Production keeps Flutter's conventional window class so that tooling which
# looks for it keeps working. The other flavors get a class of their own, so
# that single-instance forwarding can never hand one build's command line to
# another build running next to it.
set(POMODOIST_FLAVOR_WINDOW_CLASS "FLUTTER_RUNNER_WIN32_WINDOW")

if(POMODOIST_FLAVOR_NAME STREQUAL "development")
  set(POMODOIST_FLAVOR_IS_DEVELOPMENT 1)
  set(POMODOIST_FLAVOR_DISPLAY_NAME "Pomodoist Dev")
  set(POMODOIST_FLAVOR_APPLICATION_ID "com.finchforge.pomodoist.dev")
  set(POMODOIST_FLAVOR_URL_SCHEME "pomodoist-dev")
  set(POMODOIST_FLAVOR_TOAST_GUID "c4d2e8b3-6f75-4029-ab1c-3e8d7f209b45")
  set(POMODOIST_FLAVOR_WINDOW_CLASS "FLUTTER_RUNNER_WIN32_WINDOW_POMODOIST_DEV")
elseif(POMODOIST_FLAVOR_NAME STREQUAL "staging")
  set(POMODOIST_FLAVOR_IS_STAGING 1)
  set(POMODOIST_FLAVOR_DISPLAY_NAME "Pomodoist Stg")
  set(POMODOIST_FLAVOR_APPLICATION_ID "com.finchforge.pomodoist.stg")
  set(POMODOIST_FLAVOR_URL_SCHEME "pomodoist-stg")
  set(POMODOIST_FLAVOR_TOAST_GUID "b3c1d7a2-5e64-4f18-9a0b-2d7c6e1f8a34")
  set(POMODOIST_FLAVOR_WINDOW_CLASS "FLUTTER_RUNNER_WIN32_WINDOW_POMODOIST_STG")
elseif(POMODOIST_FLAVOR_NAME STREQUAL "production")
  set(POMODOIST_FLAVOR_IS_PRODUCTION 1)
else()
  message(FATAL_ERROR
    "Unknown FLUTTER_APP_FLAVOR '${FLUTTER_APP_FLAVOR}'. "
    "Pass --flavor development, --flavor staging or --flavor production.")
endif()

# The executable keeps the name `pomodoist.exe` for every flavor. The three
# builds are separated by their install directory, application id and window
# class instead, and the installer, the updater and the packaging tests all
# address the executable by name.
set(BINARY_NAME "pomodoist")

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Set the Flutter bundle destination before plugins can initialize CMake's
# default install prefix. Native dependencies such as sentry-native otherwise
# cause the final install step to target Program Files.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# multiview_desktop 1.2.1 drops DartProject's Impeller switch while building
# FlutterDesktopEngineProperties. Keep the package unchanged and bridge only
# its engine-create call through the runner-owned compatibility shim.
if(TARGET multiview_desktop_plugin)
  target_sources(multiview_desktop_plugin PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/runner/multiview_desktop_impeller_bridge.cpp")
  target_compile_options(multiview_desktop_plugin PRIVATE
    "/FI${CMAKE_CURRENT_SOURCE_DIR}/runner/multiview_desktop_impeller_bridge.h")
endif()


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
