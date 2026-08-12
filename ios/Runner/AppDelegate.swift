import Flutter
import Speech
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    WatchCompanionHost.shared.configure(with: engineBridge)
    SystemSpeechHost.shared.configure(with: engineBridge)
  }
}

private final class SystemSpeechHost {
  static let shared = SystemSpeechHost()
  private static let channelName = "pomodoist/system_speech"

  private var channel: FlutterMethodChannel?
  private var task: SFSpeechRecognitionTask?
  private var pendingResult: FlutterResult?

  func configure(with engineBridge: FlutterImplicitEngineBridge) {
    guard channel == nil,
          let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SystemSpeechHost")
    else {
      return
    }
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "prepare":
      authorize(localeIdentifier: arguments?["locale"] as? String, result: result)
    case "transcribeFile":
      guard let path = arguments?["path"] as? String, !path.isEmpty else {
        result(error("invalid_audio_path", "Recorded audio path is missing."))
        return
      }
      transcribe(
        url: URL(fileURLWithPath: path),
        localeIdentifier: arguments?["locale"] as? String,
        result: result
      )
    case "cancel":
      cancelPending()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func authorize(localeIdentifier: String?, result: @escaping FlutterResult) {
    func finish(_ status: SFSpeechRecognizerAuthorizationStatus) {
      guard status == .authorized else {
        result(error("speech_permission_denied", "Speech recognition permission was not granted."))
        return
      }
      guard let recognizer = recognizer(localeIdentifier), recognizer.isAvailable else {
        result(error("speech_unavailable", "System speech recognition is currently unavailable."))
        return
      }
      result(nil)
    }

    let status = SFSpeechRecognizer.authorizationStatus()
    if status == .notDetermined {
      SFSpeechRecognizer.requestAuthorization { authorizationStatus in
        DispatchQueue.main.async { finish(authorizationStatus) }
      }
    } else {
      finish(status)
    }
  }

  private func transcribe(
    url: URL,
    localeIdentifier: String?,
    result: @escaping FlutterResult
  ) {
    guard pendingResult == nil else {
      result(error("speech_already_active", "System speech recognition is already active."))
      return
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
      result(error("empty_recording", "Recorded audio file does not exist."))
      return
    }
    guard let recognizer = recognizer(localeIdentifier), recognizer.isAvailable else {
      result(error("speech_unavailable", "System speech recognition is currently unavailable."))
      return
    }

    let request = SFSpeechURLRecognitionRequest(url: url)
    request.shouldReportPartialResults = false
    request.taskHint = .dictation
    pendingResult = result
    task = recognizer.recognitionTask(with: request) { [weak self] recognition, recognitionError in
      DispatchQueue.main.async {
        guard let self, self.pendingResult != nil else {
          return
        }
        if let recognition, recognition.isFinal {
          let text = recognition.bestTranscription.formattedString.trimmingCharacters(
            in: .whitespacesAndNewlines
          )
          guard !text.isEmpty else {
            self.finish(error: self.error("empty_transcript", "System speech recognition returned no text."))
            return
          }
          let segments = recognition.bestTranscription.segments
          let confidence = segments.isEmpty
            ? nil
            : segments.reduce(0.0) { $0 + Double($1.confidence) } / Double(segments.count)
          self.finish(value: ["text": text, "confidence": confidence as Any])
        } else if let recognitionError {
          self.finish(
            error: self.error(
              "speech_recognition_failed",
              recognitionError.localizedDescription
            )
          )
        }
      }
    }
  }

  private func recognizer(_ localeIdentifier: String?) -> SFSpeechRecognizer? {
    guard let localeIdentifier, !localeIdentifier.isEmpty else {
      return SFSpeechRecognizer()
    }
    return SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
  }

  private func cancelPending() {
    task?.cancel()
    if pendingResult != nil {
      finish(error: error("speech_canceled", "System speech recognition was canceled."))
    }
  }

  private func finish(value: Any? = nil, error: FlutterError? = nil) {
    let result = pendingResult
    pendingResult = nil
    task = nil
    if let error {
      result?(error)
    } else {
      result?(value)
    }
  }

  private func error(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }
}
