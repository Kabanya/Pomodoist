import Cocoa
import Carbon.HIToolbox
import FlutterMacOS

enum QuickAddChannel {
  static let name = "pomodoist/quick_add"
  static let createTaskMethod = "createTask"
  static let getHintMethod = "getQuickAddHint"
}

private let quickAddHotKeySignature = OSType(0x504D5141) // PMQA
private let quickAddHotKeyIdentifier = UInt32(1)

final class QuickAddHotKeyController: NSObject, NSWindowDelegate {
  private let channel: FlutterMethodChannel
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?
  private var panel: NSPanel?
  private weak var textField: NSTextField?
  private weak var errorLabel: NSTextField?
  private weak var addButton: NSButton?
  private weak var cancelButton: NSButton?
  private var isSubmitting = false

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  deinit {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
    }
    if let eventHandlerRef {
      RemoveEventHandler(eventHandlerRef)
    }
  }

  func registerHotKey() {
    guard hotKeyRef == nil else {
      return
    }
    guard installEventHandler() else {
      return
    }

    let hotKeyID = EventHotKeyID(
      signature: quickAddHotKeySignature,
      id: quickAddHotKeyIdentifier
    )
    let status = RegisterEventHotKey(
      UInt32(kVK_Space),
      UInt32(optionKey),
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )

    if status != noErr {
      NSLog("Pomodoist quick add: failed to register Option+Space hotkey: \(status).")
    }
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
          controller.showQuickAddPanel()
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

  private func showQuickAddPanel() {
    let panel: NSPanel
    if let existingPanel = self.panel {
      panel = existingPanel
    } else {
      panel = makePanel()
      panel.center()
      self.panel = panel
    }

    errorLabel?.stringValue = ""
    refreshHint()
    NSApp.unhide(nil)
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panel.orderFrontRegardless()
    focusInput(in: panel)
  }

  private func refreshHint() {
    channel.invokeMethod(QuickAddChannel.getHintMethod, arguments: nil) { [weak self] result in
      DispatchQueue.main.async {
        guard let hint = result as? String, !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          return
        }
        self?.textField?.placeholderString = hint
      }
    }
  }

  private func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 172),
      styleMask: [.titled, .closable, .utilityWindow],
      backing: .buffered,
      defer: false
    )
    panel.title = "Добавить задачу"
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.delegate = self

    let contentView = NSView()
    contentView.translatesAutoresizingMaskIntoConstraints = false
    panel.contentView = contentView

    let titleLabel = NSTextField(labelWithString: "Добавить задачу")
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = .boldSystemFont(ofSize: 17)

    let textField = NSTextField(string: "")
    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.placeholderString = "Написать sync engine завтра p1 #App @coding 4p"
    textField.font = .systemFont(ofSize: 16)
    textField.usesSingleLineMode = true
    textField.lineBreakMode = .byTruncatingTail
    textField.target = self
    textField.action = #selector(submitQuickAdd)

    let errorLabel = NSTextField(labelWithString: "")
    errorLabel.translatesAutoresizingMaskIntoConstraints = false
    errorLabel.font = .systemFont(ofSize: 12)
    errorLabel.textColor = .systemRed
    errorLabel.lineBreakMode = .byTruncatingTail

    let cancelButton = NSButton(
      title: "Отмена",
      target: self,
      action: #selector(cancelQuickAdd)
    )
    cancelButton.translatesAutoresizingMaskIntoConstraints = false
    cancelButton.bezelStyle = .rounded
    cancelButton.keyEquivalent = "\u{1b}"

    let addButton = NSButton(
      title: "Добавить",
      target: self,
      action: #selector(submitQuickAdd)
    )
    addButton.translatesAutoresizingMaskIntoConstraints = false
    addButton.bezelStyle = .rounded
    addButton.keyEquivalent = "\r"

    let buttonStack = NSStackView(views: [cancelButton, addButton])
    buttonStack.translatesAutoresizingMaskIntoConstraints = false
    buttonStack.orientation = .horizontal
    buttonStack.alignment = .centerY
    buttonStack.distribution = .gravityAreas
    buttonStack.spacing = 8

    contentView.addSubview(titleLabel)
    contentView.addSubview(textField)
    contentView.addSubview(errorLabel)
    contentView.addSubview(buttonStack)

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
      titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
      titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

      textField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
      textField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
      textField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
      textField.heightAnchor.constraint(equalToConstant: 32),

      errorLabel.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 6),
      errorLabel.leadingAnchor.constraint(equalTo: textField.leadingAnchor),
      errorLabel.trailingAnchor.constraint(equalTo: textField.trailingAnchor),

      buttonStack.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 14),
      buttonStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
      buttonStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
    ])

    panel.initialFirstResponder = textField
    panel.defaultButtonCell = addButton.cell as? NSButtonCell

    self.textField = textField
    self.errorLabel = errorLabel
    self.addButton = addButton
    self.cancelButton = cancelButton
    return panel
  }

  private func focusInput(in panel: NSPanel) {
    guard let textField else {
      return
    }
    panel.makeFirstResponder(textField)
    textField.currentEditor()?.selectAll(nil)
  }

  @objc private func submitQuickAdd() {
    guard !isSubmitting else {
      return
    }
    let input = textField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !input.isEmpty else {
      showError("Введите текст задачи.")
      return
    }

    setSubmitting(true)
    channel.invokeMethod(QuickAddChannel.createTaskMethod, arguments: input) { [weak self] result in
      DispatchQueue.main.async {
        guard let self else {
          return
        }
        self.setSubmitting(false)

        if let error = result as? FlutterError {
          self.showError(error.message ?? "Не удалось добавить задачу.")
          return
        }
        if let resultObject = result as? NSObject,
           resultObject == FlutterMethodNotImplemented {
          self.showError("Быстрое добавление недоступно.")
          return
        }

        self.textField?.stringValue = ""
        self.errorLabel?.stringValue = ""
        self.panel?.orderOut(nil)
      }
    }
  }

  @objc private func cancelQuickAdd() {
    guard !isSubmitting else {
      return
    }
    textField?.stringValue = ""
    errorLabel?.stringValue = ""
    panel?.orderOut(nil)
  }

  private func showError(_ message: String) {
    errorLabel?.stringValue = message
    if let panel {
      focusInput(in: panel)
    }
  }

  private func setSubmitting(_ submitting: Bool) {
    isSubmitting = submitting
    textField?.isEnabled = !submitting
    cancelButton?.isEnabled = !submitting
    addButton?.isEnabled = !submitting
    addButton?.title = submitting ? "Добавление..." : "Добавить"
  }
}
