#include "../third_party/sherpa_onnx/c-api.h"

#ifdef _WIN32
#define POMODOIST_EXPORT __declspec(dllexport)
#else
#define POMODOIST_EXPORT __attribute__((visibility("default")))
#endif

// Keep the C API's versioned config layout in native code. Dart opens the
// bundled runtime and supplies the entry point, so this library has no
// link-time dependency on platform-specific Sherpa import libraries.
extern "C" POMODOIST_EXPORT const SherpaOnnxOfflineRecognizer*
PomodoistCreateWhisperRecognizer(
    decltype(&SherpaOnnxCreateOfflineRecognizer) create,
    const char* encoder, const char* decoder, const char* tokens,
    const char* language) {
  SherpaOnnxOfflineRecognizerConfig config{};
  config.feat_config.sample_rate = 16000;
  config.feat_config.feature_dim = 80;
  config.model_config.whisper.encoder = encoder;
  config.model_config.whisper.decoder = decoder;
  config.model_config.whisper.language = language;
  config.model_config.whisper.task = "transcribe";
  config.model_config.whisper.tail_paddings = -1;
  config.model_config.tokens = tokens;
  config.model_config.num_threads = 2;
  config.model_config.provider = "cpu";
  config.decoding_method = "greedy_search";
  config.max_active_paths = 4;
  return create(&config);
}
