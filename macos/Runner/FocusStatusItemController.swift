import Cocoa
import FlutterMacOS
import WidgetKit

final class FocusStatusItemController: NSObject, NSMenuDelegate {
  private static let timerColors: [(key: PomodoistTimerColor, title: String, color: NSColor)] = [
    (.white, "White", .white),
    (.black, "Black", .black),
    (.red, "Red", .systemRed),
    (.green, "Green", .systemGreen),
    (.blue, "Blue", .systemBlue),
    (.orange, "Orange", .systemOrange),
    (.purple, "Purple", .systemPurple),
  ]

  private let channel: FlutterMethodChannel
  private let store: PomodoistFocusSnapshotStore
  private let defaults: UserDefaults
  private let statusItem = NSStatusBar.system.statusItem(
    withLength: NSStatusItem.variableLength
  )
  private let menu = NSMenu()
  private var snapshot = PomodoistSnapshot.empty
  private var selectedTimerColor: PomodoistTimerColor?
  private var ticker: Timer?

  init(
    channel: FlutterMethodChannel,
    store: PomodoistFocusSnapshotStore = PomodoistFocusSnapshotStore(),
    defaults: UserDefaults = UserDefaults(suiteName: pomodoistFocusAppGroupIdentifier) ?? .standard
  ) {
    self.channel = channel
    self.store = store
    self.defaults = defaults
    let storedColor = defaults.string(forKey: pomodoistTimerColorDefaultsKey)
      ?? UserDefaults.standard.string(forKey: pomodoistTimerColorDefaultsKey)
    selectedTimerColor = storedColor.flatMap(PomodoistTimerColor.init(rawValue:))
    if let selectedTimerColor {
      defaults.set(selectedTimerColor.rawValue, forKey: pomodoistTimerColorDefaultsKey)
    }
    super.init()
    snapshot = store.load()
    configureChannel()
    configureStatusItem()
    updateStatusItem()
  }

  deinit {
    ticker?.invalidate()
    NSStatusBar.system.removeStatusItem(statusItem)
  }

  func start() {
    ticker = Timer.scheduledTimer(
      withTimeInterval: 1,
      repeats: true
    ) { [weak self] _ in
      self?.updateStatusItem()
    }
    requestSnapshot()
  }

  private func configureChannel() {
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleFlutterCall(call, result: result)
    }
  }

  private func configureStatusItem() {
    statusItem.menu = menu
    menu.delegate = self
    if let button = statusItem.button {
      button.setAccessibilityLabel("Pomodoist focus timer")
    }
  }

  private func handleFlutterCall(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "updateSnapshot":
      guard let context = call.arguments as? [String: Any] else {
        result(
          FlutterError(
            code: "invalid_snapshot",
            message: "Expected a focus snapshot dictionary.",
            details: nil
          )
        )
        return
      }
      let snapshotDictionary = (context["snapshot"] as? [String: Any]) ?? context
      applySnapshot(snapshotDictionary)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func applySnapshot(_ dictionary: [String: Any]) {
    guard let decoded = PomodoistSnapshot.decode(from: dictionary) else {
      return
    }
    snapshot = decoded
    store.save(dictionary: dictionary)
    updateStatusItem()
    WidgetCenter.shared.reloadTimelines(ofKind: pomodoistFocusWidgetKind)
  }

  private func requestSnapshot() {
    sendCommand(type: PomodoistFocusCommand.snapshotRequest)
  }

  private func updateStatusItem(now: Date = Date()) {
    guard let button = statusItem.button else {
      return
    }
    let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    let title = NSMutableAttributedString(
      string: "\u{25EF} ",
      attributes: [
        .font: font,
        .foregroundColor: NSColor.secondaryLabelColor,
      ]
    )
    let timerText = PomodoistFocusDisplay.timerText(now: now, focus: snapshot.focus)
    title.append(
      NSAttributedString(
        string: timerText,
        attributes: [
          .font: font,
          .foregroundColor: titleColor(for: snapshot.focus),
        ]
      )
    )
    button.attributedTitle = title
    button.setAccessibilityValue(
      "\(PomodoistFocusDisplay.stateLabel(focus: snapshot.focus)), \(timerText)"
    )
  }

  private func titleColor(for focus: PomodoistFocusSnapshot) -> NSColor {
    if let selectedTimerColor,
      let preset = Self.timerColors.first(where: { $0.key == selectedTimerColor })
    {
      return preset.color
    }
    guard focus.isActive, let interval = focus.interval else {
      return .systemRed
    }
    if interval.status == "paused" {
      return .secondaryLabelColor
    }
    return interval.type == "work" ? .systemRed : .systemTeal
  }

  func menuWillOpen(_ menu: NSMenu) {
    rebuildMenu()
  }

  private func rebuildMenu() {
    menu.removeAllItems()

    let focus = snapshot.focus
    let stateTitle = PomodoistFocusDisplay.stateLabel(focus: focus)
    let header = NSMenuItem(
      title: "\(stateTitle) - \(PomodoistFocusDisplay.timerText(now: Date(), focus: focus))",
      action: nil,
      keyEquivalent: ""
    )
    header.isEnabled = false
    menu.addItem(header)
    menu.addItem(.separator())

    if let startCommand = PomodoistFocusDisplay.primaryStartCommand(focus: focus) {
      let startTitle = startCommand == PomodoistFocusCommand.restartInterval
        ? "Start Interval"
        : "Start Focus"
      menu.addItem(item(title: startTitle, action: #selector(startFocus)))
    }

    if focus.isActive, let interval = focus.interval {
      let canPause = focus.preset?.allowPause ?? true
      if interval.status == "paused" {
        menu.addItem(item(title: "Resume", action: #selector(resumeFocus)))
      } else if interval.status == "running" {
        let pauseItem = item(title: "Pause", action: #selector(pauseFocus))
        pauseItem.isEnabled = canPause
        menu.addItem(pauseItem)
      }
      menu.addItem(
        item(title: "Complete Interval", action: #selector(completeInterval))
      )
      menu.addItem(item(title: "Stop", action: #selector(stopFocus)))
    }

    menu.addItem(.separator())
    menu.addItem(timerColorMenuItem())
    menu.addItem(.separator())
    menu.addItem(item(title: "Open Pomodoist", action: #selector(openPomodoist)))
    menu.addItem(item(title: "Quit", action: #selector(quit)))
  }

  private func item(title: String, action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }

  private func timerColorMenuItem() -> NSMenuItem {
    let parent = NSMenuItem(title: "Timer Color", action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: "Timer Color")

    let automatic = item(title: "Automatic", action: #selector(resetTimerColor))
    automatic.state = selectedTimerColor == nil ? .on : .off
    submenu.addItem(automatic)
    submenu.addItem(.separator())

    for preset in Self.timerColors {
      let colorItem = item(title: preset.title, action: #selector(selectTimerColor(_:)))
      colorItem.representedObject = preset.key.rawValue
      colorItem.state = selectedTimerColor == preset.key ? .on : .off
      colorItem.image = swatchImage(color: preset.color)
      submenu.addItem(colorItem)
    }

    parent.submenu = submenu
    return parent
  }

  private func swatchImage(color: NSColor) -> NSImage {
    NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
      let path = NSBezierPath(
        roundedRect: rect.insetBy(dx: 1, dy: 1),
        xRadius: 2,
        yRadius: 2
      )
      color.setFill()
      path.fill()
      NSColor.separatorColor.setStroke()
      path.lineWidth = 1
      path.stroke()
      return true
    }
  }

  @objc private func startFocus() {
    guard let command = PomodoistFocusDisplay.primaryStartCommand(focus: snapshot.focus) else {
      return
    }
    sendCommand(type: command)
  }

  @objc private func pauseFocus() {
    sendCommand(type: PomodoistFocusCommand.pause)
  }

  @objc private func resumeFocus() {
    sendCommand(type: PomodoistFocusCommand.resume)
  }

  @objc private func stopFocus() {
    sendCommand(type: PomodoistFocusCommand.stop)
  }

  @objc private func completeInterval() {
    sendCommand(type: PomodoistFocusCommand.complete)
  }

  @objc private func selectTimerColor(_ sender: NSMenuItem) {
    guard let rawValue = sender.representedObject as? String,
      let color = PomodoistTimerColor(rawValue: rawValue)
    else {
      return
    }
    selectedTimerColor = color
    defaults.set(color.rawValue, forKey: pomodoistTimerColorDefaultsKey)
    updateStatusItem()
    WidgetCenter.shared.reloadTimelines(ofKind: pomodoistFocusWidgetKind)
  }

  @objc private func resetTimerColor() {
    selectedTimerColor = nil
    defaults.removeObject(forKey: pomodoistTimerColorDefaultsKey)
    updateStatusItem()
    WidgetCenter.shared.reloadTimelines(ofKind: pomodoistFocusWidgetKind)
  }

  @objc private func openPomodoist() {
    NSApp.unhide(nil)
    NSApp.activate(ignoringOtherApps: true)
    if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
      window.makeKeyAndOrderFront(nil)
      return
    }
    NSApp.windows.first?.makeKeyAndOrderFront(nil)
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  private func sendCommand(type: String) {
    let command = PomodoistFocusCommand.make(
      type: type,
      baseSnapshotGeneratedAt: snapshot.generatedAt
    )
    channel.invokeMethod("command", arguments: command) { [weak self] response in
      guard let self else {
        return
      }
      if let reply = response as? [String: Any],
        let snapshot = reply["snapshot"] as? [String: Any]
      {
        self.applySnapshot(snapshot)
      }
    }
  }
}
