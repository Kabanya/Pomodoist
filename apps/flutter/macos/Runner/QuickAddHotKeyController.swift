import Cocoa
import Carbon.HIToolbox
import FlutterMacOS

enum QuickAddChannel {
  static let name = "pomodoist/quick_add"
  static let showQuickAddMethod = "showQuickAdd"
  static let getGlobalShortcutMethod = "getGlobalShortcut"
  static let captureGlobalShortcutMethod = "captureGlobalShortcut"
  static let cancelGlobalShortcutCaptureMethod = "cancelGlobalShortcutCapture"
  static let setGlobalShortcutMethod = "setGlobalShortcut"
  static let setGlobalShortcutEnabledMethod = "setGlobalShortcutEnabled"
}

private let quickAddHotKeySignature = OSType(0x504D5141) // PMQA
private let quickAddHotKeyIdentifier = UInt32(1)
private let quickAddHotKeyCodeDefaultsKey = "quickAdd.globalShortcut.keyCode"
private let quickAddHotKeyModifiersDefaultsKey = "quickAdd.globalShortcut.modifiers"
private let quickAddHotKeyLabelDefaultsKey = "quickAdd.globalShortcut.keyLabel"

struct QuickAddGlobalShortcut: Equatable {
  static let `default` = QuickAddGlobalShortcut(
    keyCode: UInt32(kVK_Space),
    modifiers: UInt32(optionKey),
    keyLabel: "Space"
  )

  let keyCode: UInt32
  let modifiers: UInt32
  let keyLabel: String

  init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.keyLabel = keyLabel
  }

  init?(dictionary: [String: Any]) {
    guard let keyCode = (dictionary["keyCode"] as? NSNumber)?.uint32Value,
          let keyLabel = dictionary["keyLabel"] as? String,
          let meta = dictionary["meta"] as? Bool,
          let control = dictionary["control"] as? Bool,
          let alt = dictionary["alt"] as? Bool,
          let shift = dictionary["shift"] as? Bool
    else {
      return nil
    }
    var modifiers = UInt32(0)
    if meta { modifiers |= UInt32(cmdKey) }
    if control { modifiers |= UInt32(controlKey) }
    if alt { modifiers |= UInt32(optionKey) }
    if shift { modifiers |= UInt32(shiftKey) }
    self.init(keyCode: keyCode, modifiers: modifiers, keyLabel: keyLabel)
    guard isValid else { return nil }
  }

  var isValid: Bool {
    let commandModifiers = UInt32(cmdKey | controlKey | optionKey)
    return !keyLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      modifiers & commandModifiers != 0
  }

  var dictionary: [String: Any] {
    [
      "keyCode": Int(keyCode),
      "keyLabel": keyLabel,
      "meta": modifiers & UInt32(cmdKey) != 0,
      "control": modifiers & UInt32(controlKey) != 0,
      "alt": modifiers & UInt32(optionKey) != 0,
      "shift": modifiers & UInt32(shiftKey) != 0,
    ]
  }

  var displayLabel: String {
    var value = ""
    if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
    return value + keyLabel
  }

  func save(to defaults: UserDefaults) {
    defaults.set(Int(keyCode), forKey: quickAddHotKeyCodeDefaultsKey)
    defaults.set(Int(modifiers), forKey: quickAddHotKeyModifiersDefaultsKey)
    defaults.set(keyLabel, forKey: quickAddHotKeyLabelDefaultsKey)
  }

  static func load(from defaults: UserDefaults) -> QuickAddGlobalShortcut {
    guard defaults.object(forKey: quickAddHotKeyCodeDefaultsKey) != nil,
          defaults.object(forKey: quickAddHotKeyModifiersDefaultsKey) != nil,
          let keyLabel = defaults.string(forKey: quickAddHotKeyLabelDefaultsKey)
    else {
      return .default
    }
    let shortcut = QuickAddGlobalShortcut(
      keyCode: UInt32(defaults.integer(forKey: quickAddHotKeyCodeDefaultsKey)),
      modifiers: UInt32(defaults.integer(forKey: quickAddHotKeyModifiersDefaultsKey)),
      keyLabel: keyLabel
    )
    return shortcut.isValid ? shortcut : .default
  }
}

final class QuickAddHotKeyController: NSObject {
  private let channel: FlutterMethodChannel
  private let defaults: UserDefaults
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?
  private var captureMonitor: Any?
  private var pendingCaptureResult: FlutterResult?
  private(set) var currentShortcut: QuickAddGlobalShortcut
  private(set) var isEnabled = true

  init(channel: FlutterMethodChannel, defaults: UserDefaults = .standard) {
    self.channel = channel
    self.defaults = defaults
    self.currentShortcut = QuickAddGlobalShortcut.load(from: defaults)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }
  }

  deinit {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
    }
    if let eventHandlerRef {
      RemoveEventHandler(eventHandlerRef)
    }
    stopCaptureMonitor()
  }

  func registerHotKey() {
    guard hotKeyRef == nil else {
      return
    }
    guard installEventHandler() else {
      return
    }

    let status = register(currentShortcut)

    if status != noErr {
      NSLog(
        "Pomodoist quick add: failed to register \(currentShortcut.displayLabel) hotkey: \(status)."
      )
    }
  }

  @discardableResult
  func applyEnabled(
    _ enabled: Bool,
    unregister unregisterOverride: (() -> OSStatus)? = nil
  ) -> OSStatus {
    if !enabled {
      let status: OSStatus
      if let unregisterOverride {
        status = unregisterOverride()
      } else if let hotKeyRef {
        status = UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
      } else {
        status = noErr
      }
      if status == noErr { isEnabled = false }
      return status
    }

    if hotKeyRef != nil {
      isEnabled = true
      return noErr
    }

    let status = register(currentShortcut)
    if status == noErr { isEnabled = true }
    return status
  }

  @discardableResult
  func applyShortcut(
    _ shortcut: QuickAddGlobalShortcut,
    register registerOverride: ((QuickAddGlobalShortcut) -> OSStatus)? = nil
  ) -> OSStatus {
    guard shortcut.isValid else { return OSStatus(paramErr) }
    if !isEnabled {
      currentShortcut = shortcut
      shortcut.save(to: defaults)
      return noErr
    }
    let previous = currentShortcut
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }
    let registerAction = registerOverride ?? { [weak self] value in
      self?.register(value) ?? OSStatus(-1)
    }
    let status = registerAction(shortcut)
    guard status == noErr else {
      let restoreStatus = registerAction(previous)
      if restoreStatus != noErr {
        NSLog(
          "Pomodoist quick add: failed to restore \(previous.displayLabel) hotkey: \(restoreStatus)."
        )
      }
      return status
    }
    currentShortcut = shortcut
    shortcut.save(to: defaults)
    return noErr
  }

  private func register(_ shortcut: QuickAddGlobalShortcut) -> OSStatus {
    guard installEventHandler() else { return OSStatus(-1) }
    let hotKeyID = EventHotKeyID(
      signature: quickAddHotKeySignature,
      id: quickAddHotKeyIdentifier
    )
    return RegisterEventHotKey(
      shortcut.keyCode,
      shortcut.modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )
  }

  private func installEventHandler() -> Bool {
    guard eventHandlerRef == nil else {
      return true
    }

    var eventSpec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let controllerPointer = UnsafeMutableRawPointer(
      Unmanaged.passUnretained(self).toOpaque()
    )
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData -> OSStatus in
        guard let event, let userData else {
          return noErr
        }

        var hotKeyID = EventHotKeyID()
        let parameterStatus = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )
        guard parameterStatus == noErr,
              hotKeyID.signature == quickAddHotKeySignature,
              hotKeyID.id == quickAddHotKeyIdentifier
        else {
          return noErr
        }

        let controller = Unmanaged<QuickAddHotKeyController>
          .fromOpaque(userData)
          .takeUnretainedValue()
        DispatchQueue.main.async {
          controller.channel.invokeMethod(
            QuickAddChannel.showQuickAddMethod,
            arguments: nil
          )
        }
        return noErr
      },
      1,
      &eventSpec,
      controllerPointer,
      &eventHandlerRef
    )

    if status != noErr {
      NSLog(
        "Pomodoist quick add: failed to install hotkey handler: \(status)."
      )
      return false
    }
    return true
  }

  private func handleMethodCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case QuickAddChannel.getGlobalShortcutMethod:
      result(currentShortcut.dictionary)
    case QuickAddChannel.captureGlobalShortcutMethod:
      beginShortcutCapture(result: result)
    case QuickAddChannel.cancelGlobalShortcutCaptureMethod:
      cancelShortcutCapture()
      result(nil)
    case QuickAddChannel.setGlobalShortcutEnabledMethod:
      guard let enabled = call.arguments as? Bool else {
        result(
          FlutterError(
            code: "invalid_arguments",
            message: "Expected a boolean enabled value.",
            details: nil
          )
        )
        return
      }
      let status = applyEnabled(enabled)
      guard status == noErr else {
        result(
          FlutterError(
            code: "shortcut_unavailable",
            message: "The global keyboard shortcut is unavailable.",
            details: status
          )
        )
        return
      }
      result(nil)
    case QuickAddChannel.setGlobalShortcutMethod:
      guard let arguments = call.arguments as? [String: Any],
            let shortcut = QuickAddGlobalShortcut(dictionary: arguments)
      else {
        result(
          FlutterError(
            code: "invalid_shortcut",
            message: "The keyboard shortcut is invalid.",
            details: nil
          )
        )
        return
      }
      let status = applyShortcut(shortcut)
      guard status == noErr else {
        result(
          FlutterError(
            code: "shortcut_unavailable",
            message: "The global keyboard shortcut is unavailable.",
            details: status
          )
        )
        return
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func beginShortcutCapture(result: @escaping FlutterResult) {
    guard pendingCaptureResult == nil else {
      result(
        FlutterError(
          code: "shortcut_capture_active",
          message: "A keyboard shortcut is already being captured.",
          details: nil
        )
      )
      return
    }
    pendingCaptureResult = result
    captureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
      [weak self] event in
      self?.capture(event)
      return nil
    }
  }

  private func capture(_ event: NSEvent) {
    if Int(event.keyCode) == kVK_Escape {
      cancelShortcutCapture()
      return
    }
    let shortcut = QuickAddGlobalShortcut(
      keyCode: UInt32(event.keyCode),
      modifiers: carbonModifiers(event.modifierFlags),
      keyLabel: shortcutKeyLabel(event)
    )
    guard shortcut.isValid else {
      finishShortcutCapture(
        error: FlutterError(
          code: "invalid_shortcut",
          message: "Use a key with Command, Control, or Option.",
          details: nil
        )
      )
      return
    }
    finishShortcutCapture(value: shortcut.dictionary)
  }

  private func cancelShortcutCapture() {
    guard pendingCaptureResult != nil else { return }
    finishShortcutCapture(
      error: FlutterError(
        code: "shortcut_capture_cancelled",
        message: "Keyboard shortcut capture was cancelled.",
        details: nil
      )
    )
  }

  private func finishShortcutCapture(
    value: Any? = nil,
    error: FlutterError? = nil
  ) {
    let result = pendingCaptureResult
    pendingCaptureResult = nil
    stopCaptureMonitor()
    if let error {
      result?(error)
    } else {
      result?(value)
    }
  }

  private func stopCaptureMonitor() {
    if let captureMonitor {
      NSEvent.removeMonitor(captureMonitor)
      self.captureMonitor = nil
    }
  }

  private func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    let flags = flags.intersection(.deviceIndependentFlagsMask)
    var modifiers = UInt32(0)
    if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
    if flags.contains(.control) { modifiers |= UInt32(controlKey) }
    if flags.contains(.option) { modifiers |= UInt32(optionKey) }
    if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
    return modifiers
  }

  private func shortcutKeyLabel(_ event: NSEvent) -> String {
    switch Int(event.keyCode) {
    case kVK_Space: return "Space"
    case kVK_Return: return "Enter"
    case kVK_Tab: return "Tab"
    case kVK_Delete: return "Delete"
    case kVK_ForwardDelete: return "Forward Delete"
    case kVK_Escape: return "Esc"
    case kVK_LeftArrow: return "←"
    case kVK_RightArrow: return "→"
    case kVK_UpArrow: return "↑"
    case kVK_DownArrow: return "↓"
    case kVK_Home: return "Home"
    case kVK_End: return "End"
    case kVK_PageUp: return "Page Up"
    case kVK_PageDown: return "Page Down"
    default:
      let label = event.charactersIgnoringModifiers?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased() ?? ""
      return label.isEmpty ? "Key \(event.keyCode)" : label
    }
  }

}
