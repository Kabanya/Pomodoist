import AVFoundation
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
    case "checkAccess":
      result(SystemSpeechAccess.check(arguments?["locale"] as? String))
    case "requestAccess":
      SystemSpeechAccess.request(arguments?["locale"] as? String) { result($0) }
    case "prepareRecordingStorage":
      do {
        try SystemSpeechAccess.prepareStorage(arguments?["path"] as? String ?? "")
        result(nil)
      } catch { result(flutterError(error)) }
    case "openSettings":
      guard let destination = arguments?["destination"] as? String,
            ["microphone", "speech", "dictation"].contains(destination) else {
        result(error("invalid_settings_destination", "Unsupported settings destination."))
        return
      }
      openSettings(destination, result: result)
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
        result(error(status == .restricted ? "speech_authorization_restricted" : "speech_authorization_denied", "Speech recognition permission was not granted."))
        return
      }
      guard let recognizer = SystemSpeechAccess.recognizer(localeIdentifier) else {
        result(error("speech_locale_unsupported", "The requested speech language is unsupported."))
        return
      }
      guard recognizer.isAvailable else {
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
    let status = SFSpeechRecognizer.authorizationStatus()
    guard status == .authorized else {
      result(error(status == .restricted ? "speech_authorization_restricted" : "speech_authorization_denied", "Speech recognition permission was not granted."))
      return
    }
    guard let recognizer = SystemSpeechAccess.recognizer(localeIdentifier) else {
      result(error("speech_locale_unsupported", "The requested speech language is unsupported."))
      return
    }
    guard recognizer.isAvailable else {
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
        result(self.flutterError(failure))
      }
    }
  }

  private func flutterError(_ failure: Error) -> FlutterError {
    let mapped = SystemSpeechError.classify(failure)
    return FlutterError(code: mapped.code, message: mapped.message, details: mapped.details)
  }

  private func error(_ code: String, _ message: String) -> FlutterError {
    flutterError(SystemSpeechError(code: code, message: message))
  }

  private func openSettings(_ destination: String, result: @escaping FlutterResult) {
    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:]) {
      opened in result(opened)
    }
  }
}
