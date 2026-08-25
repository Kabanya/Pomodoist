import Cocoa
import FlutterMacOS

final class AppMenuController: NSObject {
  static let channelName = "pomodoist/app_menu"

  private static let fileIdentifier = NSUserInterfaceItemIdentifier("pomodoist.file")
  private static let goIdentifier = NSUserInterfaceItemIdentifier("pomodoist.go")
  private static let settingsIdentifier = NSUserInterfaceItemIdentifier("pomodoist.settings")
  private static let sidebarIdentifier = NSUserInterfaceItemIdentifier("pomodoist.toggleSidebar")

  private let channel: FlutterMethodChannel
  private let mainMenu: NSMenu

  init(channel: FlutterMethodChannel, mainMenu: NSMenu) {
    self.channel = channel
    self.mainMenu = mainMenu
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setCommands" else {
        result(FlutterMethodNotImplemented)
        return
      }
      if let commands = call.arguments as? [String: Any] {
        self?.applyCommands(commands)
      }
      result(nil)
    }
  }

  func applyCommands(_ values: [String: Any]) {
    let commands = values.compactMapValues(AppMenuCommand.init)
    guard
      let quickAdd = commands["quickAdd"],
      let toggleSidebar = commands["toggleSidebar"],
      let settings = commands["settings"]
    else {
      return
    }

    let fileMenu = topLevelMenu(
      title: "File",
      identifier: Self.fileIdentifier,
      before: "Edit"
    )
    fileMenu.removeAllItems()
    fileMenu.addItem(menuItem(for: quickAdd, name: "quickAdd", ellipsis: true))

    installToggleSidebar(toggleSidebar)
    installSettings(settings)

    let goMenu = topLevelMenu(
      title: "Go",
      identifier: Self.goIdentifier,
      before: "Window"
    )
    goMenu.removeAllItems()
    for group in [
      ["browse", "search"],
      ["today", "upcoming", "focus", "inbox"],
      ["priorityMatrix", "timeline", "kanban", "reports"],
    ] {
      let items = group.compactMap { name in
        commands[name].map { menuItem(for: $0, name: name) }
      }
      if !goMenu.items.isEmpty, !items.isEmpty {
        goMenu.addItem(.separator())
      }
      items.forEach(goMenu.addItem)
    }
  }

  private func topLevelMenu(
    title: String,
    identifier: NSUserInterfaceItemIdentifier,
    before nextTitle: String
  ) -> NSMenu {
    if let existing = mainMenu.items.first(where: { $0.identifier == identifier }),
       let submenu = existing.submenu {
      return submenu
    }
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.identifier = identifier
    item.submenu = NSMenu(title: title)
    let nextIndex = mainMenu.indexOfItem(withTitle: nextTitle)
    mainMenu.insertItem(item, at: nextIndex >= 0 ? nextIndex : mainMenu.numberOfItems)
    return item.submenu!
  }

  private func installSettings(_ command: AppMenuCommand) {
    guard let applicationMenu = mainMenu.items.first?.submenu else {
      return
    }
    let item = applicationMenu.items.first(where: {
      $0.identifier == Self.settingsIdentifier
    }) ?? applicationMenu.items.first(where: { $0.keyEquivalent == "," })
      ?? NSMenuItem(title: "", action: nil, keyEquivalent: "")
    if item.menu == nil {
      applicationMenu.insertItem(item, at: min(2, applicationMenu.numberOfItems))
    }
    item.identifier = Self.settingsIdentifier
    configure(item, for: command, name: "settings", ellipsis: true)
  }

  private func installToggleSidebar(_ command: AppMenuCommand) {
    let viewMenu = mainMenu.item(withTitle: "View")?.submenu
      ?? topLevelMenu(
        title: "View",
        identifier: NSUserInterfaceItemIdentifier("pomodoist.view"),
        before: "Window"
      )
    let existing = viewMenu.items.first(where: {
      $0.identifier == Self.sidebarIdentifier
    })
    let item = existing ?? NSMenuItem(title: "", action: nil, keyEquivalent: "")
    if existing == nil {
      viewMenu.insertItem(item, at: 0)
      if viewMenu.numberOfItems > 1, !viewMenu.item(at: 1)!.isSeparatorItem {
        viewMenu.insertItem(.separator(), at: 1)
      }
    }
    item.identifier = Self.sidebarIdentifier
    configure(item, for: command, name: "toggleSidebar")
  }

  private func menuItem(
    for command: AppMenuCommand,
    name: String,
    ellipsis: Bool = false
  ) -> NSMenuItem {
    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    configure(item, for: command, name: name, ellipsis: ellipsis)
    return item
  }

  private func configure(
    _ item: NSMenuItem,
    for command: AppMenuCommand,
    name: String,
    ellipsis: Bool = false
  ) {
    item.title = command.label + (ellipsis ? "…" : "")
    item.target = self
    item.action = #selector(selectMenuItem(_:))
    item.representedObject = name
    item.keyEquivalent = keyEquivalent(for: command.keyLabel)
    item.keyEquivalentModifierMask = item.keyEquivalent.isEmpty ? [] : command.modifiers
    item.isEnabled = true
  }

  @objc private func selectMenuItem(_ sender: NSMenuItem) {
    guard let name = sender.representedObject as? String else {
      return
    }
    DispatchQueue.main.async { [channel] in
      channel.invokeMethod("selected", arguments: name)
    }
  }

  private func keyEquivalent(for label: String) -> String {
    let value = label.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.count == 1 {
      return value.lowercased()
    }
    let specialKeys: [String: Int] = [
      "arrow up": NSUpArrowFunctionKey,
      "arrow down": NSDownArrowFunctionKey,
      "arrow left": NSLeftArrowFunctionKey,
      "arrow right": NSRightArrowFunctionKey,
      "home": NSHomeFunctionKey,
      "end": NSEndFunctionKey,
      "page up": NSPageUpFunctionKey,
      "page down": NSPageDownFunctionKey,
      "delete": NSDeleteFunctionKey,
    ]
    let normalized = value.lowercased()
    if let key = specialKeys[normalized] {
      return functionKey(key)
    }
    if normalized.first == "f",
       let number = Int(normalized.dropFirst()),
       (1...20).contains(number) {
      return functionKey(NSF1FunctionKey + number - 1)
    }
    return switch normalized {
    case "space": " "
    case "enter", "return": "\r"
    case "tab": "\t"
    case "escape", "esc": "\u{1b}"
    case "backspace": "\u{8}"
    default: ""
    }
  }

  private func functionKey(_ value: Int) -> String {
    guard let scalar = UnicodeScalar(value) else {
      return ""
    }
    return String(Character(scalar))
  }
}

private struct AppMenuCommand {
  let label: String
  let keyLabel: String
  let modifiers: NSEvent.ModifierFlags

  init?(_ value: Any) {
    guard
      let data = value as? [String: Any],
      let label = data["label"] as? String,
      let keyLabel = data["keyLabel"] as? String,
      let meta = data["meta"] as? Bool,
      let control = data["control"] as? Bool,
      let alt = data["alt"] as? Bool,
      let shift = data["shift"] as? Bool
    else {
      return nil
    }
    self.label = label
    self.keyLabel = keyLabel
    var modifiers: NSEvent.ModifierFlags = []
    if meta { modifiers.insert(.command) }
    if control { modifiers.insert(.control) }
    if alt { modifiers.insert(.option) }
    if shift { modifiers.insert(.shift) }
    self.modifiers = modifiers
  }
}
