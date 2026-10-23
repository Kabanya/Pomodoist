# Shared by the real Thermion target and an isolated ELF loader regression.
function(pomodoist_configure_thermion_runtime_paths target native_assets_dir)
  target_link_directories(${target} BEFORE PRIVATE "${native_assets_dir}")
  # Flutter copies TARGET_FILE through install(FILES), so INSTALL_RPATH alone
  # never reaches the bundle. Keep sibling lookup in the build ELF itself;
  # the absolute native-assets fallback still supports the development tree.
  set_property(TARGET ${target} APPEND PROPERTY BUILD_RPATH "$ORIGIN" "${native_assets_dir}")
  set_property(TARGET ${target} PROPERTY INSTALL_RPATH "$ORIGIN")
endfunction()
