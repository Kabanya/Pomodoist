import AVFoundation
import Cocoa
import FlutterMacOS
import Speech
import multiview_desktop

@main
class AppDelegate: FlutterAppDelegate {
  private var quickAddHotKeyController: QuickAddHotKeyController?
  private var appMenuController: AppMenuController?
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
            appMenuController == nil ||
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

    if appMenuController == nil, let mainMenu = NSApp.mainMenu {
      let menuChannel = FlutterMethodChannel(
        name: AppMenuController.channelName,
        binaryMessenger: flutterViewController.engine.binaryMessenger
      )
      appMenuController = AppMenuController(channel: menuChannel, mainMenu: mainMenu)
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
  private let transcriber = SystemSpeechTranscriber()

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
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
    let link: String
    if destination == "dictation" {
      if #available(macOS 13.0, *) {
        link = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Dictation"
      } else {
        link = "x-apple.systempreferences:com.apple.preference.keyboard?Dictation"
      }
    } else {
      let anchor = destination == "microphone" ? "Privacy_Microphone" : "Privacy_SpeechRecognition"
      link = "x-apple.systempreferences:com.apple.preference.security?" + anchor
    }
    if NSWorkspace.shared.open(URL(string: link)!) { result(true); return }
    let settingsPath: String
    if #available(macOS 13.0, *) { settingsPath = "/System/Applications/System Settings.app" }
    else { settingsPath = "/System/Applications/System Preferences.app" }
    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: settingsPath),
      configuration: NSWorkspace.OpenConfiguration()) { app, _ in
        DispatchQueue.main.async { result(app != nil) }
      }
  }
}
