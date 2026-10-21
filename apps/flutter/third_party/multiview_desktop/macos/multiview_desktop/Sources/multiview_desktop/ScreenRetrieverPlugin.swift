import Cocoa
import FlutterMacOS

private extension NSScreen {
    var mvdDisplayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    /// Returns a dictionary describing this screen in Flutter/logical coordinate space
    /// (Y-down, origin at top-left of the primary screen).
    func toMvdDictionary() -> NSDictionary {
        var name = ""
        if #available(macOS 10.15, *) {
            name = localizedName
        }
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? frame.maxY

        // Full screen bounds in Flutter coords.
        let size: NSDictionary = [
            "width": frame.width,
            "height": frame.height,
        ]

        // Visible area (excludes Dock / menu bar) in Flutter coords.
        // visibleFrame.origin is in Cocoa coords (Y-up from primary bottom).
        let vf = visibleFrame
        let visiblePosition: NSDictionary = [
            "dx": vf.origin.x,
            "dy": primaryMaxY - vf.origin.y - vf.height,
        ]
        let visibleSize: NSDictionary = [
            "width": vf.width,
            "height": vf.height,
        ]

        return [
            "id": mvdDisplayID.description,
            "name": name,
            "size": size,
            "visiblePosition": visiblePosition,
            "visibleSize": visibleSize,
        ]
    }
}

// MARK: - MvdScreenRetrieverPlugin

class MvdScreenRetrieverPlugin: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var externalDisplayCount = 0

    static func register(with messenger: FlutterBinaryMessenger) {
        let instance = MvdScreenRetrieverPlugin()

        let methodChannel = FlutterMethodChannel(
            name: "multiview_desktop/screen_retriever",
            binaryMessenger: messenger
        )
        methodChannel.setMethodCallHandler(instance.handle)

        let eventChannel = FlutterEventChannel(
            name: "multiview_desktop/screen_retriever_event",
            binaryMessenger: messenger
        )
        eventChannel.setStreamHandler(instance)

        instance.externalDisplayCount = NSScreen.screens.count
        instance.setupNotificationCenter()
    }

    // MARK: FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // MARK: Private

    private func setupNotificationCenter() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDisplayChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func handleDisplayChange(notification: Notification) {
        let current = NSScreen.screens.count
        if externalDisplayCount < current {
            emitEvent("display-added")
        } else if externalDisplayCount > current {
            emitEvent("display-removed")
        }
        externalDisplayCount = current
    }

    private func emitEvent(_ eventName: String) {
        guard let sink = eventSink else { return }
        sink(["type": eventName] as NSDictionary)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getCursorScreenPoint":
            getCursorScreenPoint(result: result)
        case "getPrimaryDisplay":
            guard let screen = NSScreen.screens.first else {
                result(FlutterError(code: "NO_SCREEN", message: "No primary display found", details: nil))
                return
            }
            result(screen.toMvdDictionary())
        case "getAllDisplays":
            result(["displays": NSScreen.screens.map { $0.toMvdDictionary() }] as NSDictionary)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Returns cursor position in Flutter logical coords (Y-down from primary screen top).
    private func getCursorScreenPoint(result: @escaping FlutterResult) {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? (NSScreen.main?.frame.maxY ?? 0)
        let mouseLocation = NSEvent.mouseLocation
        result(["dx": mouseLocation.x, "dy": primaryMaxY - mouseLocation.y] as NSDictionary)
    }
}
