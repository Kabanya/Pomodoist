import AppKit
import ApplicationServices

// An expendable document app and external UI observer. Never targets user apps.
@main
struct BlockingFixture {
  @MainActor static var window: NSWindow!
  @MainActor static var input: NSTextField!
  @MainActor static var pomodoist: NSRunningApplication?
  @MainActor static var draft = ""
  static var targetExecutable: String {
    CommandLine.arguments.first(where: { $0.hasPrefix("--target=") }).map { String($0.dropFirst(9)) } ?? ""
  }

  static func emit(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
    fflush(stdout)
  }

  @MainActor static func main() {
    let app = NSApplication.shared
    let onConsole = (CGSessionCopyCurrentDictionary() as? [String: Any])?["kCGSSessionOnConsoleKey"] as? Bool == true
    if CommandLine.arguments.contains("--preflight") {
      emit([
        "desktop": onConsole && !NSScreen.screens.isEmpty,
        "accessibility": AXIsProcessTrusted(),
        "postEvents": CGPreflightPostEventAccess(),
      ])
      return
    }
    app.setActivationPolicy(.regular)
    let menu = NSMenu()
    let file = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    file.submenu = NSMenu(title: "File")
    file.submenu!.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    menu.addItem(file)
    app.mainMenu = menu
    window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 520, height: 200),
                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Pomodoist E2E expendable document"
    window.isReleasedWhenClosed = false
    input = NSTextField(frame: NSRect(x: 30, y: 80, width: 450, height: 32))
    input.stringValue = "keep native draft"
    input.setAccessibilityIdentifier("e2e-document")
    window.contentView!.addSubview(input)
    window.makeKeyAndOrderFront(nil)
    emit(["ready": true, "pid": ProcessInfo.processInfo.processIdentifier,
          "bundle": Bundle.main.bundleIdentifier ?? "missing",
          "name": NSRunningApplication.current.localizedName ?? "missing"])
    DispatchQueue.global().async {
      while let line = readLine() {
        guard let data = line.data(using: .utf8),
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
        Task { @MainActor in
          do {
            let result = try await command(request)
            emit(["id": request["id"] ?? 0, "result": result])
          } catch {
            if let pid = pomodoist?.processIdentifier {
              let target = AXUIElementCreateApplication(pid)
              let windows = attribute(target, kAXWindowsAttribute) as? [AXUIElement] ?? []
              func describe(_ element: AXUIElement) -> [String: String] {
                Dictionary(uniqueKeysWithValues: [kAXTitleAttribute, kAXDescriptionAttribute, kAXRoleAttribute, kAXSubroleAttribute].map {
                  ($0, String(describing: attribute(element, $0)))
                })
              }
              let visible = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [])
                .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
                .map { ["layer": $0[kCGWindowLayer as String] ?? -1, "number": $0[kCGWindowNumber as String] ?? -1] }
              emit(["diagnostics": true, "front": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none",
                    "targetActive": pomodoist?.isActive ?? false, "documentActive": NSApp.isActive,
                    "windows": windows.map(describe),
                    "visibleWindows": visible,
                    "focusedWindow": attribute(target, kAXFocusedWindowAttribute).map { describe($0 as! AXUIElement) } ?? [:]])
            }
            emit(["id": request["id"] ?? 0, "error": String(describing: error)])
          }
        }
      }
      DispatchQueue.main.async { NSApp.terminate(nil) }
    }
    app.run()
  }

  struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
  }

  @MainActor static func check(_ value: Bool, _ message: String) throws {
    if !value { throw CheckFailure(message) }
  }

  @MainActor static func wait(_ message: String, until condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(10)
    while !condition() {
      try check(Date() < deadline, message)
      try await Task.sleep(nanoseconds: 100_000_000)
    }
  }

  static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
  }

  @MainActor static func shields() -> [AXUIElement] {
    guard let pid = pomodoist?.processIdentifier else { return [] }
    let app = AXUIElementCreateApplication(pid)
    let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    return windows.filter {
      (attribute($0, kAXDescriptionAttribute) as? String) == "Focus protection" ||
      (attribute($0, kAXTitleAttribute) as? String) == "Focus protection"
    }
  }

  static func returnButton(_ element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    if (attribute(element, kAXTitleAttribute) as? String) == "Return to task" ||
        (attribute(element, kAXDescriptionAttribute) as? String) == "Return to task in Pomodoist" { return element }
    if depth >= 10 { return nil }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
      if let button = returnButton(child, depth: depth + 1) { return button }
    }
    return nil
  }

  @MainActor static func key(_ code: CGKeyCode, text: String? = nil, flags: CGEventFlags = []) throws {
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    try check(front == pomodoist?.processIdentifier || front == ProcessInfo.processInfo.processIdentifier,
              "Refusing to send keys: an unrelated app owns keyboard focus")
    for down in [true, false] {
      guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else {
        throw CheckFailure("Cannot create keyboard event")
      }
      event.flags = flags
      if let text = text {
        let chars = Array(text.utf16)
        chars.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: $0.baseAddress!) }
      }
      event.post(tap: .cghidEventTap)
    }
  }

  @MainActor static func activateDocument() async throws {
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(input)
    NSApp.activate(ignoringOtherApps: true)
    try await wait("Fixture activation reached neither document nor shield") { NSApp.isActive || !shields().isEmpty }
  }

  @MainActor static func command(_ request: [String: Any]) async throws -> [String: Any] {
    if let pid = request["pid"] as? Int32 {
      let target = NSRunningApplication(processIdentifier: pid)
      try check(target?.bundleIdentifier == "com.finchforge.pomodoist.dev.e2e" &&
                target?.executableURL?.resolvingSymlinksInPath().path == URL(fileURLWithPath: targetExecutable).resolvingSymlinksInPath().path,
                "Target must be the isolated test Runner: actual=\(target?.bundleIdentifier ?? "missing") \(target?.executableURL?.path ?? "missing"), expected=\(targetExecutable)")
      try check(pomodoist == nil || pomodoist?.processIdentifier == pid, "Target PID cannot change during a test")
      pomodoist = target
    }
    switch request["step"] as? String {
    case "register":
      try check(pomodoist != nil, "Test Runner PID is required")
    case "cleanup":
      // LaunchServices may create a second app outside Flutter's process group.
      // A unique temporary executable path establishes ownership for both.
      for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.finchforge.pomodoist.dev.e2e")
        where app.executableURL?.resolvingSymlinksInPath().path == URL(fileURLWithPath: targetExecutable).resolvingSymlinksInPath().path && !app.isTerminated {
        try check(app.forceTerminate(), "Cannot terminate the owned test Runner")
        try await wait("Owned test Runner did not terminate") { app.isTerminated }
      }
    case "discover":
      try await activateDocument()
      try await Task.sleep(nanoseconds: 600_000_000)
      pomodoist?.activate(options: [.activateIgnoringOtherApps])
    case "before":
      try await activateDocument()
      try key(0, text: "a")
      try await wait("Unprotected document did not receive a real key") { input.stringValue != "keep native draft" }
      draft = input.stringValue
      try check(shields().isEmpty, "Protection appeared before Focus")
      pomodoist?.activate(options: [.activateIgnoringOtherApps])
    case "blocked":
      try await activateDocument()
      try await wait("No real Focus protection window appeared") { !shields().isEmpty && pomodoist?.isActive == true }
      let app = AXUIElementCreateApplication(pomodoist!.processIdentifier)
      let focused = attribute(app, kAXFocusedWindowAttribute)
      try check(focused != nil && shields().contains { CFEqual($0, focused!) }, "Shield does not own keyboard focus")
      try key(0, text: "z")
      try key(13, flags: .maskCommand)
      try await Task.sleep(nanoseconds: 500_000_000)
      try check(input.stringValue == draft && window.isVisible, "Blocked keyboard input changed or closed the document")
      try check(!shields().isEmpty, "Cmd-W dismissed the shield")
      guard let panel = shields().first, let button = returnButton(panel) else { throw CheckFailure("Return to task button missing") }
      try check(AXUIElementPerformAction(button, kAXPressAction as CFString) == .success, "Cannot press Return to task")
      try await wait("Return to task did not dismiss the shield") { shields().isEmpty }
    case "after":
      try check(shields().isEmpty, "Shield remains after stopping Focus")
      try await activateDocument()
      try check(input.stringValue == draft && window.isVisible, "Document contents were lost")
      try key(0, text: "b")
      try await wait("Released document did not receive a real key") { input.stringValue != draft }
      try check(shields().isEmpty, "Document is still blocked after Focus")
      try key(13, flags: .maskCommand)
      try await wait("Fixture does not handle Cmd-W when unprotected") { !window.isVisible }
      pomodoist?.activate(options: [.activateIgnoringOtherApps])
    default: throw CheckFailure("Unknown native test step")
    }
    return ["ok": true]
  }
}
