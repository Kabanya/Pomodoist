import Cocoa
import FlutterMacOS

/// An activating key panel keeps covered applications out of the responder chain.
final class DistractionShieldPanel: NSPanel {
  init(frame: NSRect) {
    super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    becomesKeyOnlyIfNeeded = false
    hidesOnDeactivate = true
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
  override func performClose(_ sender: Any?) {}
  override func cancelOperation(_ sender: Any?) {}
  override func keyDown(with event: NSEvent) {}

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.keyCode == 53 ||
        (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "w") {
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}

/// A public-API foreground shield. It never closes, suspends, or edits another app.
final class DistractionProtectionController {
  private let channel: FlutterMethodChannel
  private var observers: [NSObjectProtocol] = []
  private var activationObserver: NSObjectProtocol?
  private var sessionActive = true
  private var timer: Timer?
  private var discovery = false
  private var quitAllowed = false
  private var lastDiscovered: String?
  var protectionActive: Bool { !quitAllowed && (deadline.map { $0 > Date() } ?? false) }
  func requestQuit() { channel.invokeMethod("requestQuit", arguments: nil) }
  private var blocked = Set<String>()
  private var deadline: Date?
  private var remaining = 0
  private var countdown = true
  private var updatedAt = Date()
  private var task = "Focus"
  private var image: NSImage?
  private var panels: [DistractionShieldPanel] = []
  private var takingShieldFocus = false
  private var activationDeadline: Date?
  private var labels: [NSTextField] = []
  private var attempted: String?
  private let excluded = Set(["com.apple.finder", "com.apple.loginwindow", "com.apple.systempreferences", "com.apple.SecurityAgent", "com.apple.systemuiserver", "com.apple.dock"])

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    activationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main
    ) { [weak self] _ in self?.finishShieldFocus() }
    observers.append(NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.inspect() })
    observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
      self?.sessionActive = false; self?.hideShield()
    })
    observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      self?.sessionActive = true; self?.inspect()
    })
  }

  deinit {
    if let activationObserver = activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    timer?.invalidate()
    panels.forEach { $0.close() }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capabilities":
      result(["supported": true, "platform": "macos", "discoveryAvailable": true,
              "adapter": "workspace-shield", "limitations": "Foreground shield only; background audio may continue. System and security apps are excluded."])
    case "allowQuit": quitAllowed = true; clear(); result(nil); NSApp.terminate(nil)
    case "startDiscovery": discovery = true; lastDiscovered = nil; inspect(); result(nil)
    case "stopDiscovery": discovery = false; result(nil)
    case "clearProtection": clear(); result(nil)
    case "setProtection":
      guard let args = call.arguments as? [String: Any], let active = args["active"] as? Bool else {
        result(FlutterError(code: "invalid_protection", message: "Missing protection state.", details: nil)); return
      }
      if !active { clear(); result(nil); return }
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      let plain = ISO8601DateFormatter()
      guard let ids = args["blockedApps"] as? [String], ids.count <= 4096,
            ids.allSatisfy({ $0.count <= 512 && !$0.contains("/") && !$0.contains("\\") }),
            let title = args["taskTitle"] as? String, title.count <= 4096,
            let seconds = args["remainingSeconds"] as? Int, seconds >= 0,
            let iso = args["expiresAt"] as? String,
            let expires = formatter.date(from: iso) ?? plain.date(from: iso) else {
        result(FlutterError(code: "invalid_protection", message: "Invalid protection snapshot.", details: nil)); return
      }
      guard expires > Date() else { clear(); result(nil); return }
      blocked = Set(ids); deadline = expires; task = title.isEmpty ? "Focus" : title
      remaining = seconds; countdown = args["countdown"] as? Bool ?? true; updatedAt = Date()
      if let bytes = args["mascotImage"] as? FlutterStandardTypedData, bytes.data.count <= 8 * 1024 * 1024 {
        image = NSImage(data: bytes.data)
      }
      timer?.invalidate()
      timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.inspect() }
      // Keep a focused shield mounted across task/timer snapshot updates.
      let wasShieldFocused = NSApp.isActive && panels.contains { $0 === NSApp.keyWindow }
      hideShield()
      if wasShieldFocused, let attempted = attempted, blocked.contains("macos:\(attempted)") {
        showShield()
      } else {
        inspect()
      }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func clear() {
    blocked.removeAll(); deadline = nil; timer?.invalidate(); timer = nil
    attempted = nil; hideShield()
  }

  private func inspect() {
    if let expires = deadline, Date() >= expires { clear() }
    // A refused activation must leave the next inspection free to retry.
    if let activationDeadline = activationDeadline, Date() >= activationDeadline { hideShield() }
    guard discovery || deadline != nil else { return }
    guard sessionActive else { hideShield(); return }
    guard let app = NSWorkspace.shared.frontmostApplication else { hideShield(); return }
    if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
      if takingShieldFocus || panels.contains(where: { $0 === NSApp.keyWindow }) {
        for label in labels { label.stringValue = timeText() }
      } else {
        hideShield()
      }
      return
    }
    guard let bundle = app.bundleIdentifier,
          app.activationPolicy == .regular, !excluded.contains(bundle) else { hideShield(); return }
    let payload = ["id": "macos:\(bundle)", "name": app.localizedName ?? bundle, "platform": "macos"]
    if discovery && lastDiscovered != bundle { lastDiscovered = bundle; channel.invokeMethod("foregroundApp", arguments: payload) }
    guard deadline != nil, blocked.contains("macos:\(bundle)") else {
      attempted = nil; hideShield(); return
    }
    if attempted != bundle { channel.invokeMethod("blockedAttempt", arguments: payload); attempted = bundle }
    // An app-owned panel can cover sandboxed/full-screen apps without AX access.
    if panels.isEmpty { showShield() } else { focusShield() }
    for label in labels { label.stringValue = timeText() }
  }

  private func timeText() -> String {
    let seconds = max(0, remaining - (countdown ? Int(Date().timeIntervalSince(updatedAt)) : 0))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private func showShield() {
    for screen in NSScreen.screens {
      let panel = DistractionShieldPanel(frame: screen.frame)
      panel.level = .screenSaver
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      panel.backgroundColor = .windowBackgroundColor
      panel.isOpaque = true; panel.isReleasedWhenClosed = false
      panel.setAccessibilityLabel("Focus protection")
      let stack = NSStackView()
      stack.orientation = .vertical; stack.spacing = 20; stack.alignment = .centerX
      if let image = image {
        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityLabel("Pomo focusing")
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: 180), view.heightAnchor.constraint(equalToConstant: 180)])
        stack.addArrangedSubview(view)
      }
      let title = NSTextField(wrappingLabelWithString: task)
      title.font = .systemFont(ofSize: 24, weight: .semibold); title.alignment = .center
      stack.addArrangedSubview(title)
      let time = NSTextField(labelWithString: timeText())
      time.font = .monospacedDigitSystemFont(ofSize: 28, weight: .medium)
      labels.append(time); stack.addArrangedSubview(time)
      let button = NSButton(title: "Return to task", target: self, action: #selector(returnToTask))
      button.bezelStyle = .rounded; button.keyEquivalent = "\r"
      button.setAccessibilityLabel("Return to task in Pomodoist")
      stack.addArrangedSubview(button)
      panel.initialFirstResponder = button
      guard let content = panel.contentView else { continue }
      stack.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(stack)
      NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: content.centerXAnchor), stack.centerYAnchor.constraint(equalTo: content.centerYAnchor), stack.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, multiplier: 0.8)])
      panels.append(panel)
    }
    focusShield()
  }

  private func focusShield() {
    guard !panels.isEmpty, !takingShieldFocus else { return }
    takingShieldFocus = true
    activationDeadline = Date().addingTimeInterval(1)
    // Never cover a foreign key window while waiting for application activation.
    panels.forEach { $0.orderOut(nil) }
    NSApp.activate(ignoringOtherApps: true)
    if NSApp.isActive {
      finishShieldFocus()
    }
  }

  private func finishShieldFocus() {
    guard takingShieldFocus else { return }
    defer { takingShieldFocus = false; activationDeadline = nil }
    guard sessionActive, protectionActive, NSApp.isActive,
          let keyPanel = panels.first(where: { $0.screen === NSScreen.main }) ?? panels.first else {
      hideShield(); return
    }
    keyPanel.makeKeyAndOrderFront(nil)
    guard NSApp.isActive, keyPanel.isKeyWindow else { hideShield(); return }
    panels.filter { $0 !== keyPanel }.forEach { $0.orderFrontRegardless() }
    keyPanel.makeFirstResponder(keyPanel.initialFirstResponder)
  }

  private func hideShield() { takingShieldFocus = false; activationDeadline = nil; panels.forEach { $0.close() }; panels.removeAll(); labels.removeAll() }

  @objc private func returnToTask() {
    hideShield()
    NSApp.activate(ignoringOtherApps: true)
    // The shield is independent of the companion; bring back the main Flutter window.
    NSApp.windows.first { !($0 is NSPanel) && $0.contentViewController is FlutterViewController }?.makeKeyAndOrderFront(nil)
  }
}
