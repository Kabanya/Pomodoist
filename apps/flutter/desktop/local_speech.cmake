add_library(pomodoist_local_speech SHARED "${CMAKE_CURRENT_LIST_DIR}/local_speech.cc")
add_dependencies(${BINARY_NAME} pomodoist_local_speech)
install(TARGETS pomodoist_local_speech
  LIBRARY DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime
  RUNTIME DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
install(FILES "${CMAKE_CURRENT_LIST_DIR}/../third_party/sherpa_onnx/LICENSE"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/licenses/sherpa-onnx" COMPONENT Runtime)
