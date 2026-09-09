import Cocoa
import FlutterMacOS

final class MacosGlassController {
  static let channelName = "pomodoist/macos_glass"

  private final class GlassView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }

  private final class WindowState {
    weak var controller: FlutterViewController?
    weak var window: NSWindow?
    let controllerBackgroundColor: NSColor?
    let windowBackgroundColor: NSColor
    let windowWasOpaque: Bool
    var effectView: GlassView?
    var requestedEnabled = false
    var dark = false

    init(controller: FlutterViewController, window: NSWindow) {
      self.controller = controller
      self.window = window
      controllerBackgroundColor = controller.backgroundColor
      windowBackgroundColor = window.backgroundColor
      windowWasOpaque = window.isOpaque
    }
  }

  private let channel: FlutterMethodChannel
  private var states: [UInt64: WindowState] = [:]
  private var accessibilityObserver: NSObjectProtocol?
  private var windowObserver: NSObjectProtocol?

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.accessibilityOptionsChanged()
    }
    windowObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let window = notification.object as? NSWindow else { return }
      self?.states = self?.states.filter { $0.value.window !== window } ?? [:]
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
    if let accessibilityObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
    }
    if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "setGlass" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let arguments = call.arguments as? [String: Any],
          let viewIdNumber = arguments["viewId"] as? NSNumber,
          CFGetTypeID(viewIdNumber) != CFBooleanGetTypeID(),
          viewIdNumber.doubleValue.isFinite,
          viewIdNumber.doubleValue == Double(viewIdNumber.int64Value),
          viewIdNumber.int64Value >= 0,
          let enabledNumber = arguments["enabled"] as? NSNumber,
          CFGetTypeID(enabledNumber) == CFBooleanGetTypeID(),
          let darkNumber = arguments["dark"] as? NSNumber,
          CFGetTypeID(darkNumber) == CFBooleanGetTypeID() else {
      result(FlutterError(
        code: "invalid_arguments",
        message: "setGlass requires viewId:int, enabled:bool, and dark:bool.",
        details: nil
      ))
      return
    }

    let enabled = enabledNumber.boolValue
    let dark = darkNumber.boolValue
    let viewId = UInt64(viewIdNumber.int64Value)
    guard let controller = flutterViewController(viewId: viewId),
          let window = controller.view.window else {
      result(FlutterError(
        code: "window_not_found",
        message: "No macOS Flutter window exists for viewId \(viewId).",
        details: nil
      ))
      return
    }

    let state = states[viewId] ?? WindowState(controller: controller, window: window)
    states[viewId] = state
    state.requestedEnabled = enabled
    state.dark = dark
    let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    apply(state, reduceTransparency: reduceTransparency)
    result(["enabled": enabled && !reduceTransparency, "reduceTransparency": reduceTransparency])
  }

  private func flutterViewController(viewId: UInt64) -> FlutterViewController? {
    for window in NSApp.windows {
      if let controller = findFlutterViewController(
        viewId: viewId,
        in: window.contentViewController
      ) {
        return controller
      }
    }
    return nil
  }

  private func findFlutterViewController(
    viewId: UInt64,
    in controller: NSViewController?
  ) -> FlutterViewController? {
    guard let controller else { return nil }
    if let flutterController = controller as? FlutterViewController,
       UInt64(flutterController.viewIdentifier) == viewId {
      return flutterController
    }
    for child in controller.children {
      if let flutterController = findFlutterViewController(viewId: viewId, in: child) {
        return flutterController
      }
    }
    return nil
  }

  private func apply(_ state: WindowState, reduceTransparency: Bool) {
    guard let controller = state.controller, let window = state.window else { return }
    guard state.requestedEnabled else {
      state.effectView?.removeFromSuperview()
      state.effectView = nil
      controller.backgroundColor = state.controllerBackgroundColor
      window.backgroundColor = state.windowBackgroundColor
      window.isOpaque = state.windowWasOpaque
      return
    }

    let appearance = NSAppearance(named: state.dark ? .darkAqua : .aqua) ?? window.effectiveAppearance
    if reduceTransparency {
      state.effectView?.removeFromSuperview()
      state.effectView = nil
      var fallback = NSColor.windowBackgroundColor
      appearance.performAsCurrentDrawingAppearance {
        fallback = NSColor(cgColor: NSColor.windowBackgroundColor.cgColor) ?? fallback
      }
      controller.backgroundColor = fallback
      window.backgroundColor = fallback
      window.isOpaque = true
      return
    }

    let effect = state.effectView ?? GlassView(frame: controller.view.bounds)
    effect.autoresizingMask = [.width, .height]
    effect.material = .underWindowBackground
    effect.blendingMode = .behindWindow
    effect.state = .followsWindowActiveState
    effect.appearance = appearance
    effect.setAccessibilityElement(false)
    if effect.superview == nil {
      controller.view.addSubview(effect, positioned: .below, relativeTo: nil)
    }
    state.effectView = effect
    controller.backgroundColor = .clear
    window.backgroundColor = .clear
    window.isOpaque = false
  }

  private func accessibilityOptionsChanged() {
    let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    states = states.filter { $0.value.window != nil && $0.value.controller != nil }
    for state in states.values where state.requestedEnabled {
      if reduceTransparency { apply(state, reduceTransparency: true) }
    }
    channel.invokeMethod(
      "transparencyChanged",
      arguments: ["reduceTransparency": reduceTransparency]
    )
  }
}
