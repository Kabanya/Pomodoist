import Cocoa
import FlutterMacOS
import Speech
import multiview_desktop

@main
class AppDelegate: FlutterAppDelegate {
  private var quickAddHotKeyController: QuickAddHotKeyController?
  private var focusStatusItemController: FocusStatusItemController?
  private var systemSpeechHost: SystemSpeechHost?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    configureNativeControllers()
  }

  override func applicationDidBecomeActive(_ notification: Notification) {
    configureNativeControllers()
  }

  func configureNativeControllers(
    with providedFlutterViewController: FlutterViewController? = nil
  ) {
    guard quickAddHotKeyController == nil ||
            focusStatusItemController == nil ||
            systemSpeechHost == nil
    else {
      return
    }

    guard
      let flutterViewController = providedFlutterViewController
        ?? resolveFlutterViewController(
          mainWindow: mainFlutterWindow,
          windows: NSApp.windows
        )
    else {
      return
    }

    if quickAddHotKeyController == nil {
      let channel = FlutterMethodChannel(
        name: QuickAddChannel.name,
        binaryMessenger: flutterViewController.engine.binaryMessenger
      )
      quickAddHotKeyController = QuickAddHotKeyController(channel: channel)
    }

    if focusStatusItemController == nil {
      let focusChannel = FlutterMethodChannel(
        name: watchCompanionChannelName,
        binaryMessenger: flutterViewController.engine.binaryMessenger
      )
      focusStatusItemController = FocusStatusItemController(channel: focusChannel)
      focusStatusItemController?.start()
    }

    if systemSpeechHost == nil {
      let speechChannel = FlutterMethodChannel(
        name: SystemSpeechHost.channelName,
        binaryMessenger: flutterViewController.engine.binaryMessenger
      )
      systemSpeechHost = SystemSpeechHost(channel: speechChannel)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return MultiviewDesktopPlugin.applicationShouldTerminateAfterLastWindowClosed()
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if MultiviewDesktopPlugin.applicationShouldHandleReopen(
      sender,
      hasVisibleWindows: flag
    ) {
      return true
    }
    if !flag {
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
      sender.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    return MultiviewDesktopPlugin.applicationShouldTerminate(sender)
  }

  override func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    return MultiviewDesktopPlugin.applicationDockMenu(sender)
  }
}

private final class SystemSpeechHost {
  static let channelName = "pomodoist/system_speech"

  private let channel: FlutterMethodChannel
  private var task: SFSpeechRecognitionTask?
  private var pendingResult: FlutterResult?

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
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
