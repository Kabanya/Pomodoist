import Cocoa
import FlutterMacOS
import multiview_desktop

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let engine = FlutterEngine(
      name: "main_flutter_engine",
      project: nil,
      allowHeadlessExecution: true
    )
    MultiviewDesktopPlugin.prepareEngine(engine, window: self)
    let flutterViewController = FlutterViewController(
      engine: engine,
      nibName: nil,
      bundle: nil
    )
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: false)

    RegisterGeneratedPlugins(registry: flutterViewController)
    PomoWindowBridge.shared.register(engine.binaryMessenger)
    StoreKitHost.register(with: flutterViewController.registrar(forPlugin: "StoreKitHost"))

    super.awakeFromNib()

    (NSApp.delegate as? AppDelegate)?.configureNativeControllers(
      with: flutterViewController
    )
  }
}

/// Per-window hit regions. Polls only while the companion is visible; requires no
/// accessibility permission and installs no global keyboard/mouse event hook.
private final class PomoWindowBridge {
  static let shared = PomoWindowBridge()
  private var timer: Timer?
  private weak var window: NSWindow?
  private var paths: [NSBezierPath] = []
  private var channel: FlutterMethodChannel?
  func register(_ messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "pomodoist/pomo_window", binaryMessenger: messenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self, let args = call.arguments as? [String: Any],
            let id = args["viewId"] as? Int64 else {
        result(FlutterError(code: "arguments", message: "Missing Pomo view", details: nil)); return
      }
      if call.method == "detach" {
        self.timer?.invalidate(); self.timer = nil
        self.window?.ignoresMouseEvents = false; self.window = nil
        result(nil); return
      }
      guard let window = NSApp.windows.first(where: {
        ($0.contentViewController as? FlutterViewController)?.viewIdentifier == id
      }) else {
        result(FlutterError(code: "window", message: "Pomo window unavailable", details: nil)); return
      }
      let top = NSScreen.screens.first?.frame.maxY ?? 0
      if call.method == "bounds" {
        result(["x": window.frame.minX, "y": top-window.frame.maxY,
                "width": window.frame.width, "height": window.frame.height, "scale": 1.0]); return
      }
      if call.method == "move", let x = args["x"] as? Double, let y = args["y"] as? Double {
        window.setFrameOrigin(NSPoint(x: x, y: top-y-window.frame.height)); result(nil); return
      }
      guard call.method == "configure", let regions = args["regions"] as? [[String: Any]] else {
        result(FlutterMethodNotImplemented); return
      }
      if self.window !== window {
        self.window = window
        // Configure the backing surface once, not on every menu/input-region change.
        // Clearing NSWindow alone leaves Flutter's backing surface opaque black.
        (window.contentViewController as? FlutterViewController)?.backgroundColor = .clear
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.collectionBehavior.insert(.canJoinAllSpaces)
      }
      self.paths = regions.compactMap { region in
        guard let x = region["x"] as? Double, let y = region["y"] as? Double,
              let width = region["width"] as? Double, let height = region["height"] as? Double else { return nil }
        let rect = NSRect(x: x, y: y, width: width, height: height)
        if region["rectangle"] as? Bool == true { return NSBezierPath(rect: rect) }
        return region["rounded"] as? Bool == true
          ? NSBezierPath(roundedRect: rect, xRadius: height/2, yRadius: height/2)
          : NSBezierPath(ovalIn: rect)
      }
      if self.timer == nil {
        self.timer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in self?.updateHitTest() }
      }
      self.updateHitTest(); result(nil)
    }
  }
  private func updateHitTest() {
    guard let window, window.isVisible, let content = window.contentView else { return }
    // Preserve a drag that started in a hit region until its button is released.
    if NSEvent.pressedMouseButtons != 0 && !window.ignoresMouseEvents { return }
    let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
    let local = content.convert(point, from: nil)
    let flutter = NSPoint(x: local.x, y: content.isFlipped ? local.y : content.bounds.height-local.y)
    let ignoresMouseEvents = !paths.contains(where: { $0.contains(flutter) })
    if window.ignoresMouseEvents != ignoresMouseEvents {
      window.ignoresMouseEvents = ignoresMouseEvents
    }
  }
}
