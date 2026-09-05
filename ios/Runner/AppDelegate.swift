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
  private let transcriber = SystemSpeechTranscriber()

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
      transcriber.cancel()
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
    guard let recognizer = recognizer(localeIdentifier), recognizer.isAvailable else {
      result(error("speech_unavailable", "System speech recognition is currently unavailable."))
      return
    }
    transcriber.transcribe(
      url: url, locale: localeIdentifier, onDevice: recognizer.supportsOnDeviceRecognition
    ) { outcome in
      switch outcome {
      case .success(let transcript):
        var value: [String: Any] = ["text": transcript.text]
        if let confidence = transcript.confidence { value["confidence"] = confidence }
        result(value)
      case .failure(let failure):
        result(FlutterError(
          code: (failure as? SystemSpeechError)?.code ?? "speech_recognition_failed",
          message: failure.localizedDescription,
          details: nil
        ))
      }
    }
  }

  private func recognizer(_ localeIdentifier: String?) -> SFSpeechRecognizer? {
    guard let localeIdentifier, !localeIdentifier.isEmpty else {
      return SFSpeechRecognizer()
    }
    return SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
  }

  private func error(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }
}
