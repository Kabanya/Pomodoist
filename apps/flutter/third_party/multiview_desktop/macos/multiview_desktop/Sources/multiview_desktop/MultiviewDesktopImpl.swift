import Cocoa
import FlutterMacOS

// MARK: - NSRect coordinate helpers

/// Extends NSRect with a `topLeft` property that converts between Cocoa
/// (Y-up, origin at bottom-left of primary screen) and Flutter/logical
/// (Y-down, origin at top-left of primary screen) coordinate spaces.
///
/// The getter returns the Flutter top-left point for the rect.
/// The setter moves the rect so that its top-left corner is at the given
/// Flutter point, picking the best target screen by overlap area.
extension NSRect {
    var topLeft: CGPoint {
        get {
            func overlapArea(_ r: CGRect) -> CGFloat {
                if r.isNull || r.isEmpty {
                    return 0
                }
                return r.width * r.height
            }

            let screens = NSScreen.screens
            let targetScreen: NSScreen? = screens.max {
                overlapArea(self.intersection($0.frame)) < overlapArea(self.intersection($1.frame))
            } ?? NSScreen.main ?? screens.first
            let sf = targetScreen?.frame
                ?? NSScreen.main?.frame
                ?? NSScreen.screens.first?.frame
                ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
            return CGPoint(x: origin.x, y: sf.maxY - origin.y - size.height)
        }
        set {
            func overlapArea(_ r: CGRect) -> CGFloat {
                if r.isNull || r.isEmpty {
                    return 0
                }
                return r.width * r.height
            }

            let screens = NSScreen.screens
            // Pick the screen that would contain the most of the window after the move.
            let targetScreen: NSScreen? = screens.max {
                let o0 = CGPoint(x: newValue.x, y: $0.frame.maxY - newValue.y - size.height)
                let o1 = CGPoint(x: newValue.x, y: $1.frame.maxY - newValue.y - size.height)
                return overlapArea(CGRect(origin: o0, size: size).intersection($0.frame))
                    < overlapArea(CGRect(origin: o1, size: size).intersection($1.frame))
            } ?? NSScreen.main ?? screens.first
            let sf = targetScreen?.frame
                ?? NSScreen.main?.frame
                ?? NSScreen.screens.first?.frame
                ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
            origin.x = newValue.x
            origin.y = sf.maxY - newValue.y - size.height
        }
    }
}

// A frameless companion can accept explicit keyboard focus without becoming
// the application main window. Passive appearance itself never activates it.
private class DesktopSecondaryWindow: NSWindow {
    var passive = false
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { !passive }
}

// MARK: - Per-window state

/// Mutable close / maximize flags for one [NSWindow], keyed by Flutter view ID.
private class WindowState {
    var focusOnShow = true
    /// When `true`, `windowShouldClose` emits `close` and returns `false`.
    var isPreventClose: Bool = false
    /// When `true`, `windowShouldClose` may destroy the window.
    var isConfirmClose: Bool = false
    var isMaximized: Bool = false
    /// window: `false` until cascade / pre-close logic finishes.
    var isPreConfirm: Bool = false
}

// MARK: - MultiviewDesktopImpl

/// Singleton that owns the shared Flutter engine, all OS windows, and the
/// single `multiview_desktop` method channel.
class MultiviewDesktopImpl: NSObject, NSWindowDelegate {

    static let shared: MultiviewDesktopImpl = MultiviewDesktopImpl()

    private var hasTaskbarCallback = false

    /// Second pass of `applicationShouldTerminate` after Dart approved quit.
    private var isConfirmTerminate = false

    /// Set in `windowWillClose` when the closing window is the last managed one.
    private var isClosingLastWindow = false

    weak var engine: FlutterEngine?

    // Temporary main NSWindow reference stored during prepareEngine(_:),
    // consumed in register(with:) once the viewIdentifier is available.
    var mainWindowRef: NSWindow?

    // All managed OS windows keyed by FlutterViewIdentifier.
    var windows: [Int64: NSWindow] = [:]

    /// Flutter view ID of the main window (set in [registerMain] for [mainWindowRef]).
    private(set) var mainViewId: Int64?

    private var windowStates: [Int64: WindowState] = [:]
    /// Maps a sheet (modal dialog) viewId to the NSWindow it is attached to.
    /// Populated in [createModalDialogWindow]; cleared when the sheet is dismissed.
    private var sheetParents: [Int64: NSWindow] = [:]
    private var channel: FlutterMethodChannel?

    /// Mirrors Dart [CloseMode]: `false` when windows are hidden instead of closed ([CloseMode.macos]).
    private var terminateAfterLastWindowClosed: Bool = true

    private struct TaskbarMenuEntry {
        let id: Int
        let title: String
        let image: NSImage?
    }

    private var taskbarMenuEntries: [TaskbarMenuEntry] = []

    // MARK: - Channel setup

    /// Binds the `multiview_desktop` method channel to this singleton.
    func setup(messenger: FlutterBinaryMessenger) {
        let ch = FlutterMethodChannel(
            name: "multiview_desktop",
            binaryMessenger: messenger
        )
        ch.setMethodCallHandler { [weak self] call, result in
            self?.handle(call: call, result: result)
        }
        channel = ch
    }

    // MARK: - Window registration

    /// Tracks [window] and installs `NSWindowDelegate` for lifecycle events.
    func registerWindow(_ window: NSWindow, viewId: Int64) {
        windows[viewId] = window
        windowStates[viewId] = WindowState()
        window.delegate = self
        // if let mainWindowRef, window === mainWindowRef {
        //     mainViewId = viewId
        // }
    }

    func registerMain(_ window: NSWindow, viewId: Int64) {
        windows[viewId] = window
        windowStates[viewId] = WindowState()
        window.delegate = self
        mainViewId = viewId
    }

    // MARK: - Dock (macOS hide-instead-of-quit)

    /// Single entry for Cmd+Q and for last-window close (which bypasses
    /// `applicationShouldTerminateAfterLastWindowClosed` when this override exists).
    func handleApplicationShouldTerminate(sender: Any?) -> NSApplication.TerminateReply {
        if isConfirmTerminate {
            isConfirmTerminate = false
            return .terminateNow
        }

        let closingLastWindow = isClosingLastWindow
        isClosingLastWindow = false

        // Same policy as `applicationShouldTerminateAfterLastWindowClosed`: stay in dock.
        if closingLastWindow && terminateAfterLastWindowClosed {
            return .terminateNow
        }

        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod(
                "onEvent",
                arguments: ["eventName": "applicationShouldTerminateRequest"]
            )
        }
        return .terminateCancel
    }

    func replyToApplicationShouldTerminate(terminate: Bool) {
        isConfirmTerminate = terminate
        if terminate {
            NSApp.terminate(nil)
        }
    }

    /// Replaces dock menu items configured from Dart via `setTaskbarMenu`.
    func setTaskbarMenu(items: [[String: Any]]) {
        taskbarMenuEntries = items.compactMap { dict in
            guard let id = int(from: dict["id"]),
                  let title = dict["title"] as? String else {
                return nil
            }
            var image: NSImage?
            if let iconBase64 = dict["icon"] as? String,
               let data = Data(base64Encoded: iconBase64) {
                image = NSImage(data: data)
            }
            return TaskbarMenuEntry(id: id, title: title, image: image)
        }
    }

    /// Builds the dock context menu for `applicationDockMenu(_:)`.
    func applicationDockMenu() -> NSMenu? {
        guard !taskbarMenuEntries.isEmpty else {
            return nil
        }
        let menu = NSMenu()
        for entry in taskbarMenuEntries {
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(onTaskbarMenuItemSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = entry.id
            if let image = entry.image {
                item.image = image
            }
            menu.addItem(item)
        }
        return menu
    }

    @objc private func onTaskbarMenuItemSelected(_ sender: NSMenuItem) {
        channel?.invokeMethod(
            "onEvent",
            arguments: ["eventName": "taskbarMenuItemSelected", "id": sender.tag]
        )
    }


    /// Call from `applicationShouldHandleReopen(_:hasVisibleWindows:)` when the dock icon is clicked.
    ///
    /// Returns `true` when the plugin handled the click (`onTaskbarTap` or restore).
    /// The AppDelegate must return `false` to AppKit (do not call `super`) so the
    /// default reopen path does not also cycle windows across Spaces.
    @discardableResult
    func handleApplicationReopen(hasVisibleWindows: Bool) -> Bool {
        if hasTaskbarCallback {
            DispatchQueue.main.async { [weak self] in
                self?.channel?.invokeMethod(
                    "onEvent",
                    arguments: ["eventName": "taskbar-callback"]
                )
            }
            let hiddenEntries = windows.filter {
                !$0.value.isVisible
            }
            guard !hiddenEntries.isEmpty else {
                return true
            }

        }
        if hasVisibleWindows {
            return false
        }
        return showHiddenWindowsIfNeeded()
    }

    /// Restores hidden windows only for an explicit Dock reopen, not app activation
    /// from interacting with or dismissing a companion window.
    @discardableResult
    private func showHiddenWindowsIfNeeded() -> Bool {
        guard !windows.isEmpty else {
            return false
        }
        guard !windows.values.contains(where: { $0.isVisible }) else {
            return false
        }

        let hiddenEntries = windows.filter {
            !$0.value.isVisible
        }
        guard !hiddenEntries.isEmpty else {
            return false
        }

        // Prefer the anchor window so Dart/native stay in sync after dock click.
        let targetId: Int64
        let targetWindow: NSWindow
        if let mainViewId, let anchorWindow = windows[mainViewId], !anchorWindow.isVisible {
            targetId = mainViewId
            targetWindow = anchorWindow
        } else if let firstHidden = hiddenEntries.first {
            targetId = firstHidden.key
            targetWindow = firstHidden.value
            mainViewId = targetId
        } else {
            return false
        }

        windowStates[targetId]?.isPreConfirm = false
        focusWindow(targetWindow)
        return true
    }

    /// Forward from `AppDelegate.applicationShouldTerminateAfterLastWindowClosed(_:)`.
    func shouldTerminateAfterLastWindowClosed() -> Bool {
        terminateAfterLastWindowClosed
    }

    func setTerminateAfterLastWindowClosed(_ terminate: Bool) {
        terminateAfterLastWindowClosed = terminate
    }

    func setHasTaskbarCallback(_ hasCallback: Bool) {
        hasTaskbarCallback = hasCallback
    }

    // MARK: - Channel handler

    private func handle(call: FlutterMethodCall, result: FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        case "checkExistViewId":
            let viewId = int64(from: args, key: "viewId")
            result(windows[viewId] != nil)
        case "createWindow":
            createSecondaryWindow(args: args, result: result)
        case "createModalDialog":
            createModalDialogWindow(args: args, result: result)
        case "applicationShouldTerminateResponse":
            let terminate = args["terminate"] as? Bool ?? false
            replyToApplicationShouldTerminate(terminate: terminate)
            result(nil)
        case "setTerminateAfterLastWindowClosed":
            let terminate = args["terminateAfterLastWindowClosed"] as? Bool ?? true
            setTerminateAfterLastWindowClosed(terminate)
            result(nil)
        case "setHasTaskbarCallback":
            let hasCallback = args["hasTaskbarCallback"] as? Bool ?? false
            setHasTaskbarCallback(hasCallback)
            result(nil)
        case "setAnchorViewId":
            let anchorId = int64(from: args, key: "viewId")
            mainViewId = anchorId
            result(nil)
        case "isHideAppFromTaskbar":
            result(NSApplication.shared.activationPolicy() == .accessory)
        case "hideAppFromTaskbar":
            let isSkipTaskbar: Bool = args["isHideAppFromTaskbar"] as? Bool ?? false
            NSApplication.shared.setActivationPolicy(isSkipTaskbar ? .accessory : .regular)
            result(nil)
        case "setProgressBar":
            let progress: CGFloat = CGFloat(truncating: args["progress"] as? NSNumber ?? 0)
            let dockTile: NSDockTile = NSApp.dockTile

            let firstTime = dockTile.contentView == nil || dockTile.contentView?.subviews.count == 0
            if firstTime {
                let imageView = NSImageView()
                imageView.image = NSApp.applicationIconImage
                dockTile.contentView = imageView

                let frame = NSMakeRect(0.0, 0.0, dockTile.size.width, 15.0)
                let progressIndicator = NSProgressIndicator(frame: frame)
                progressIndicator.style = .bar
                progressIndicator.isIndeterminate = false
                progressIndicator.minValue = 0
                progressIndicator.maxValue = 1
                progressIndicator.isHidden = false
                dockTile.contentView?.addSubview(progressIndicator)
            }

            let progressIndicator = dockTile.contentView!.subviews.last as! NSProgressIndicator
            if progress < 0 {
                progressIndicator.isHidden = true
            } else if progress > 1 {
                progressIndicator.isHidden = false
                progressIndicator.isIndeterminate = true
                progressIndicator.doubleValue = 1
            } else {
                progressIndicator.isHidden = false
                progressIndicator.doubleValue = Double(progress)
            }
            dockTile.display()

            result(nil)
        case "setTaskbarMenu":
            let items = args["items"] as? [[String: Any]] ?? []
            setTaskbarMenu(items: items)
            result(nil)
        default:
            let viewId = int64(from: args, key: "viewId")
            if let window = windows[viewId] {
                handleViewMethod(call: call, result: result, window: window, viewId: viewId)
            } else {
                result(FlutterError(
                    code: "NO_WINDOW",
                    message: "No window for viewId \(viewId)",
                    details: nil
                ))
            }
        }
    }

    // MARK: - Secondary window creation

    private func createSecondaryWindow(args: [String: Any], result: FlutterResult) {
        guard let engine else {
            result(FlutterError(code: "NO_ENGINE", message: "Engine not available", details: nil))
            return
        }

        let token = args["token"] as? Int ?? 0
        let width = args["width"] as? CGFloat ?? 800
        let height = args["height"] as? CGFloat ?? 600
        let title = args["title"] as? String ?? ""
        let position = args["position"] as? [String: Any]
        let titleBarStyleName = args["titleBarStyle"] as? String ?? "normal"
        let windowButtonVisibility = args["windowButtonVisibility"] as? Bool ?? true

        let newController = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        let viewId = newController.viewIdentifier

        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

        let newWindow = DesktopSecondaryWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        newWindow.contentViewController = newController
        // contentViewController assignment resets the window size to the VC's
        // initial frame; restore the requested size.
        newWindow.setContentSize(NSSize(width: width, height: height))
        newWindow.title = title
        newWindow.isReleasedWhenClosed = false
        // hide window from taskbar & window menu
//        newWindow.isExcludedFromWindowsMenu = true

        if titleBarStyleName == "hidden" {
            newWindow.titleVisibility = .hidden
            newWindow.titlebarAppearsTransparent = true
            newWindow.styleMask.insert(.fullSizeContentView)
        }
        newWindow.standardWindowButton(.closeButton)?.isHidden = !windowButtonVisibility
        newWindow.standardWindowButton(.miniaturizeButton)?.isHidden = !windowButtonVisibility
        newWindow.standardWindowButton(.zoomButton)?.isHidden = !windowButtonVisibility

        if let position,
           let x = cgFloat(from: position["x"]),
           let y = cgFloat(from: position["y"]) {
            var frameRect = newWindow.frame
            frameRect.topLeft = CGPoint(x: x, y: y)
            newWindow.setFrameOrigin(frameRect.origin)
        } else {
            newWindow.center()
        }

        registerWindow(newWindow, viewId: viewId)
        let focusOnShow = args["focusOnShow"] as? Bool ?? true
        windowStates[viewId]?.focusOnShow = focusOnShow
        newWindow.passive = !focusOnShow
        if focusOnShow {
            NSApp.activate(ignoringOtherApps: true)
            newWindow.makeKeyAndOrderFront(nil)
        }

        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod(
                "onEvent",
                arguments: ["eventName": "viewCreated", "viewId": Int(viewId), "token": token]
            )
        }

        result(nil)
    }

    // MARK: - Modal dialog (sheet)

    /// Creates a modal dialog window attached to its parent via `NSWindow.beginSheet(_:)`.
    ///
    /// The sheet slides down from the parent's title bar, dims the parent window,
    /// and blocks all user input to it until the sheet is dismissed.  When the
    /// sheet window is closed through the normal soft-close cycle, `endSheet` is
    /// called automatically in `windowShouldClose` before the window is destroyed.
    private func createModalDialogWindow(args: [String: Any], result: FlutterResult) {
        guard let engine else {
            result(FlutterError(code: "NO_ENGINE", message: "Engine not available", details: nil))
            return
        }

        let token = args["token"] as? Int ?? 0
        let parentId = int64(from: args, key: "parentId")

        guard let parentWindow = windows[parentId] else {
            result(FlutterError(
                code: "NO_PARENT",
                message: "No parent window for viewId \(parentId)",
                details: nil
            ))
            return
        }

        let width  = args["width"]  as? CGFloat ?? 400
        let height = args["height"] as? CGFloat ?? 300
        let title  = args["title"]  as? String  ?? ""
        let modal  = args["modal"]  as? Bool  ?? false
        let position = args["position"] as? [String: Any]
        let titleBarStyleName      = args["titleBarStyle"]         as? String ?? "normal"
        let windowButtonVisibility = args["windowButtonVisibility"] as? Bool   ?? true

        let newController = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        let viewId = newController.viewIdentifier

        // Sheets are typically non-miniaturizable and non-zoomable.
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable]

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        newWindow.contentViewController = newController
        newWindow.setContentSize(NSSize(width: width, height: height))
        newWindow.title = title
        newWindow.isReleasedWhenClosed = false

        if titleBarStyleName == "hidden" {
            newWindow.titleVisibility = .hidden
            newWindow.titlebarAppearsTransparent = true
            newWindow.styleMask.insert(.fullSizeContentView)
        }
        // Sheets do not have miniaturize / zoom traffic-light buttons.
        newWindow.standardWindowButton(.closeButton)?.isHidden    = !windowButtonVisibility
        newWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        newWindow.standardWindowButton(.zoomButton)?.isHidden        = true

        registerWindow(newWindow, viewId: viewId)

        if modal {
            parentWindow.beginSheet(newWindow)
            sheetParents[viewId] = parentWindow
        } else {
            if let position,
            let x = cgFloat(from: position["x"]),
            let y = cgFloat(from: position["y"]) {
                var frameRect = newWindow.frame
                frameRect.topLeft = CGPoint(x: x, y: y)
                newWindow.setFrameOrigin(frameRect.origin)
            } else {
                newWindow.center()
            }
//            newWindow.makeKeyAndOrderFront(nil)
        }

        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod(
                "onEvent",
                arguments: ["eventName": "viewCreated", "viewId": Int(viewId), "token": token]
            )
        }

        result(nil)
    }

    // MARK: - Soft close

    /// Emits the next soft-close event for [viewId].
    ///
    /// Returns `false` when an event was emitted and the window must stay open;
    /// returns `true` when all soft-close flags are satisfied.
    @discardableResult
    private func advanceSoftClose(viewId: Int64) -> Bool {
        let state = windowStates[viewId] ?? WindowState()

        if !state.isPreConfirm {
            emitEvent("preconfirm-close", viewId: viewId)
            return false
        }

        if state.isPreventClose {
            emitEvent("close", viewId: viewId)
            return false
        }

        if !state.isConfirmClose {
            emitEvent("confirm-close", viewId: viewId)
            return false
        }

        return true
    }

    /// Dismisses a modal sheet and destroys its window.
    private func closeSheetWindow(_ sheet: NSWindow, viewId: Int64) {
        if let parentWindow = sheetParents[viewId] {
            sheetParents.removeValue(forKey: viewId)
            parentWindow.endSheet(sheet)
        }
        sheet.close()
    }

    /// Requests soft close, working around AppKit ignoring [NSWindow.performClose]
    /// while [NSWindow.attachedSheet] is non-nil.
    private func requestSoftClose(viewId: Int64, window: NSWindow) {
        if window.attachedSheet != nil {
            _ = advanceSoftClose(viewId: viewId)
            return
        }
        window.performClose(nil)
    }

    // MARK: - NSWindowDelegate

    /// Implements soft-close: main pre-confirm -> prevent-close -> confirm-close -> destroy.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let viewId = viewIdForWindow(sender) else {
            return true
        }

        if !advanceSoftClose(viewId: viewId) {
            return false
        }

        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              let viewId = viewIdForWindow(closingWindow)
        else {
            return
        }

        if windows.count <= 1 {
            isClosingLastWindow = true
        }

        if let parentWindow = sheetParents[viewId] {
            parentWindow.endSheet(closingWindow)
            sheetParents.removeValue(forKey: viewId)
        }

        windows.removeValue(forKey: viewId)
        windowStates.removeValue(forKey: viewId)
        closingWindow.delegate = nil
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        guard let viewId = viewIdForWindow(window) else {
            return true
        }
        emitEvent("maximize", viewId: viewId)
        return true
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window),
              let state = windowStates[viewId]
        else {
            return
        }

        emitEvent("resize", viewId: viewId)

        if !state.isMaximized && window.isZoomed {
            state.isMaximized = true
            emitEvent("maximize", viewId: viewId)
        }
        if state.isMaximized && !window.isZoomed {
            state.isMaximized = false
            emitEvent("unmaximize", viewId: viewId)
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("resized", viewId: viewId)
    }

    func windowWillMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("move", viewId: viewId)
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("moved", viewId: viewId)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("focus", viewId: viewId)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("blur", viewId: viewId)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("minimize", viewId: viewId)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("restore", viewId: viewId)
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("enter-full-screen", viewId: viewId)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("leave-full-screen", viewId: viewId)
    }

    // MARK: - Per-view method handler

    private func handleViewMethod(
        call: FlutterMethodCall,
        result: FlutterResult,
        window: NSWindow,
        viewId: Int64
    ) {
        let args = call.arguments as? [String: Any]
        let state = windowStates[viewId] ?? WindowState()

        switch call.method {



        case "closeWindow":
            requestSoftClose(viewId: viewId, window: window)
            result(nil)

        case "destroyWindow":
            // Synchronous forced destruction; bypasses windowShouldClose entirely.
            // Modal sheets must endSheet before close so the parent is unblocked.
            closeSheetWindow(window, viewId: viewId)
            result(nil)

        case "isPreventClose":
            result(state.isPreventClose)

        case "setPreventClose":
            state.isPreventClose = args?["isPreventClose"] as? Bool ?? false
            result(nil)

        case "confirmClose":
            state.isConfirmClose = args?["confirmClose"] as? Bool ?? true
            result(nil)

        case "preConfirmClose":
            state.isPreConfirm = args?["preConfirmClose"] as? Bool ?? false
            result(nil)

        case "setTitle":
            window.title = args?["title"] as? String ?? ""
            result(nil)

        case "getTitleBarStyle":
            let titleBarStyle: String = window.titleVisibility == .hidden ? "hidden" : "normal"

            let closeVisibility: Bool? = !(window.standardWindowButton(.closeButton)?.isHidden ?? true)
            let minimizeVisibility: Bool? = !(window.standardWindowButton(.miniaturizeButton)?.isHidden ?? true)
            let maximizeVisibility: Bool? = !(window.standardWindowButton(.zoomButton)?.isHidden ?? true)
            let res: [String: Any] = [
                "style": titleBarStyle,
                "closeVisibility": closeVisibility as Any,
                "maximizeVisibility": maximizeVisibility as Any,
                "minimizeVisibility": minimizeVisibility as Any
            ]

            result(res)

        case "setTitleBarStyle":
            let titleBarStyle: String = args?["titleBarStyle"] as? String ?? "normal"
            let closeVisibility: Bool = args?["closeVisibility"] as? Bool ?? true
            let maximizeVisibility: Bool = args?["maximizeVisibility"] as? Bool ?? true
            let minimizeVisibility: Bool = args?["minimizeVisibility"] as? Bool ?? true

            if titleBarStyle == "hidden" {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
            } else {
                window.titleVisibility = .visible
                window.titlebarAppearsTransparent = false
                window.styleMask.remove(.fullSizeContentView)
            }

            window.isOpaque = false
            window.hasShadow = true

            // The superview chain may be absent for sheet windows whose title-bar
            // structure differs from a standard top-level window; skip safely.
            if let titleBarView = window.standardWindowButton(.closeButton)?.superview?.superview {
                titleBarView.isHidden = false
            }

            window.standardWindowButton(.closeButton)?.isHidden = !closeVisibility
            window.standardWindowButton(.miniaturizeButton)?.isHidden = !minimizeVisibility
            window.standardWindowButton(.zoomButton)?.isHidden = !maximizeVisibility

            result(nil)

        case "setAsFrameless":
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.isOpaque = true
            window.hasShadow = false
            window.backgroundColor = NSColor.clear

            if window.styleMask.contains(.titled) {
                let titleBarView: NSView = (window.standardWindowButton(.closeButton)?.superview)!.superview!
                titleBarView.isHidden = true
            }

            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true

            result(nil)

        case "show":
            DispatchQueue.main.async {
                if self.windowStates[viewId]?.focusOnShow == false {
                    window.orderFrontRegardless()
                } else {
                    self.focusWindow(window)
                }
            }
            result(nil)

        case "hide":
            DispatchQueue.main.async {
                window.orderOut(nil)
            }
            result(nil)

        case "isVisible":
            result(window.isVisible)

        case "focus":
            focusWindow(window)
            result(nil)

        case "blur":
            window.resignKey()
            result(nil)

        case "isFocused":
            result(isWindowFocused(window))

        case "isOnActiveSpace":
            result(window.isOnActiveSpace)

        case "maximize":
            if !window.isZoomed {
                window.zoom(nil)
            }
            result(nil)

        case "unmaximize":
            if window.isZoomed {
                window.zoom(nil)
            }
            result(nil)

        case "isMaximized":
            result(window.isZoomed)

        case "minimize":
            window.miniaturize(nil)
            result(nil)

        case "restore":
            window.deminiaturize(nil)
            result(nil)

        case "isMinimized":
            result(window.isMiniaturized)

        case "isFullScreen":
            result(window.styleMask.contains(.fullScreen))

        case "setFullScreen":
            let isFullScreen = args?["isFullScreen"] as? Bool ?? false
            if isFullScreen != window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            result(nil)

        case "getBounds":
            let frame = window.frame
            let tl = frame.topLeft
            result([
                       "x": tl.x,
                       "y": tl.y,
                       "width": frame.width,
                       "height": frame.height,
                   ])

        case "setSize":
            var f = window.frame
            f.size = NSSize(
                width: args?["width"] as? CGFloat ?? f.width,
                height: args?["height"] as? CGFloat ?? f.height
            )
            window.setFrame(f, display: true)
            result(nil)

        case "setPosition":
            var frameRect = window.frame
            if let x = args?["x"] as? CGFloat, let y = args?["y"] as? CGFloat {
                frameRect.topLeft = CGPoint(x: x, y: y)
                window.setFrameOrigin(frameRect.origin)
            }
            result(nil)

        case "center":
            window.center()
            result(nil)

        case "setMinimumSize":
            window.minSize = NSSize(
                width: args?["width"] as? CGFloat ?? 0,
                height: args?["height"] as? CGFloat ?? 0
            )
            result(nil)

        case "setMaximumSize":
            window.maxSize = NSSize(
                width: args?["width"] as? CGFloat ?? CGFloat.greatestFiniteMagnitude,
                height: args?["height"] as? CGFloat ?? CGFloat.greatestFiniteMagnitude
            )
            result(nil)

        case "setAspectRatio":
            let ratio = args?["aspectRatio"] as? Double ?? 0.0
            if ratio > 0 {
                window.contentAspectRatio = NSSize(width: ratio, height: 1.0)
            } else {
                window.resizeIncrements = NSSize(width: 1, height: 1)
            }
            result(nil)

        case "isResizable":
            result(window.styleMask.contains(.resizable))

        case "setResizable":
            let v = args?["isResizable"] as? Bool ?? true
            if v {
                window.styleMask.insert(.resizable)
            } else {
                window.styleMask.remove(.resizable)
            }
            result(nil)

        case "isMovable":
            result(window.isMovable)

        case "setMovable":
            window.isMovable = args?["isMovable"] as? Bool ?? true
            result(nil)

        case "isMinimizable":
            result(window.styleMask.contains(.miniaturizable))

        case "setMinimizable":
            let v = args?["isMinimizable"] as? Bool ?? true
            if v {
                window.styleMask.insert(.miniaturizable)
            } else {
                window.styleMask.remove(.miniaturizable)
            }
            result(nil)

        case "isMaximizable":
            result(window.standardWindowButton(.zoomButton)?.isEnabled ?? true)

        case "setMaximizable":
            window.standardWindowButton(.zoomButton)?.isEnabled = args?["isMaximizable"] as? Bool ?? true
            result(nil)

        case "isClosable":
            result(window.styleMask.contains(.closable))

        case "setClosable":
            let v = args?["isClosable"] as? Bool ?? true
            if v {
                window.styleMask.insert(.closable)
            } else {
                window.styleMask.remove(.closable)
            }
            result(nil)

        case "isAlwaysOnTop":
            result(window.level == .floating)

        case "setAlwaysOnTop":
            window.level = (args?["isAlwaysOnTop"] as? Bool ?? false) ? .floating : .normal
            result(nil)

        case "isHideFromCollection":
            result(window.collectionBehavior.contains(.ignoresCycle))

        case "hideFromCollection":
            let v = args?["isHideFromCollection"] as? Bool ?? false
            if v {
                window.collectionBehavior.insert(.ignoresCycle)
                window.collectionBehavior.insert(.transient)
            } else {
                window.collectionBehavior.remove(.ignoresCycle)
                window.collectionBehavior.remove(.transient)
            }
            result(nil)

        case "hasShadow":
            result(window.hasShadow)

        case "setHasShadow":
            window.hasShadow = args?["hasShadow"] as? Bool ?? true
            result(nil)

        case "getOpacity":
            result(Double(window.alphaValue))

        case "setOpacity":
            window.alphaValue = CGFloat(args?["opacity"] as? Double ?? 1.0)
            result(nil)

        case "setBrightness":
            let name = args?["brightness"] as? String ?? "light"
            window.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
            result(nil)

        case "setBackgroundColor":
            let a = args?["backgroundColorA"] as? Int ?? 255
            let r = args?["backgroundColorR"] as? Int ?? 255
            let g = args?["backgroundColorG"] as? Int ?? 255
            let b = args?["backgroundColorB"] as? Int ?? 255
            window.backgroundColor = NSColor(
                calibratedRed: CGFloat(r) / 255,
                green: CGFloat(g) / 255,
                blue: CGFloat(b) / 255,
                alpha: CGFloat(a) / 255
            )
            result(nil)

        case "isVisibleOnAllWorkspaces":
            result(window.collectionBehavior.contains(.canJoinAllSpaces))

        case "setVisibleOnAllWorkspaces":
            let visible = args?["visible"] as? Bool ?? false
            let onFullScreen = args?["visibleOnFullScreen"] as? Bool ?? false
            if visible {
                window.collectionBehavior.insert(.canJoinAllSpaces)
                if onFullScreen {
                    window.collectionBehavior.insert(.fullScreenAuxiliary)
                }
            } else {
                window.collectionBehavior.remove(.canJoinAllSpaces)
                window.collectionBehavior.remove(.fullScreenAuxiliary)
            }
            result(nil)

        case "setBadgeLabel":
            NSApp.dockTile.badgeLabel = args?["label"] as? String
            result(nil)


        case "setIgnoreMouseEvents":
            let ignore: Bool = args?["ignore"] as? Bool ?? false
            let forward: Bool = args?["forward"] as? Bool ?? false
            window.ignoresMouseEvents = ignore
            if !ignore {
                window.acceptsMouseMovedEvents = false
            } else {
                window.acceptsMouseMovedEvents = forward
            }

            result(nil)

        case "isIgnoreMouseEvents":
            let ignore: Bool = window.ignoresMouseEvents
            let forward: Bool = window.acceptsMouseMovedEvents && ignore
            let res: [String: Bool] = [
                "ignore": ignore,
                "forward": forward
            ]

            result(res)

        case "startResizing":
            //TODO
            result(nil)

        case "startDragging":
            if let event = NSApp.currentEvent {
                window.performDrag(with: event)
            }
            result(nil)

        case "popUpWindowMenu":
            DispatchQueue.main.async {
                guard let contentView = window.contentView,
                      let event = NSApp.currentEvent
                else {
                    return
                }
                let menu = NSMenu()
                if window.styleMask.contains(.miniaturizable) {
                    menu.addItem(NSMenuItem(
                        title: "Minimize",
                        action: #selector(NSWindow.miniaturize(_:)),
                        keyEquivalent: ""
                    ))
                }
                menu.addItem(NSMenuItem(
                    title: "Zoom",
                    action: #selector(NSWindow.zoom(_:)),
                    keyEquivalent: ""
                ))
                if window.styleMask.contains(.closable) {
                    menu.addItem(.separator())
                    menu.addItem(NSMenuItem(
                        title: "Close",
                        action: #selector(NSWindow.performClose(_:)),
                        keyEquivalent: ""
                    ))
                }
                NSMenu.popUpContextMenu(menu, with: event, for: contentView)
            }
            result(nil)

        case "getTitle":
            result(window.title)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Helpers

    /// Brings [window] to the front.
    ///
    /// Dock / `AppleSpacesSwitchOnActivate` applies the Space switch *asynchronously*
    /// after activate/reopen. A synchronous `orderFront`+`makeKey` while the window
    /// is still `isOnActiveSpace` loses that race: the pending teleport runs afterward.
    /// Deferred retries re-check: once the window is off the active Space,
    /// `makeKeyAndOrderFront` pulls Mission Control back to it.
    private func focusWindow(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Whether [window] currently has user focus.
    ///
    /// `isKeyWindow` alone is not enough: it can stay `true` for a window that
    /// is ordered behind another window of this app, or for a window on another
    /// Space while the user is looking at a different Space.
    private func isWindowFocused(_ window: NSWindow) -> Bool {
        guard NSApp.isActive, window.isKeyWindow, window.isVisible, !window.isMiniaturized else {
            return false
        }
        guard window.isOnActiveSpace else {
            return false
        }
        for ordered in NSApp.orderedWindows {
            guard windows.contains(where: { $0.value === ordered }) else { continue }
            guard ordered.isVisible, !ordered.isMiniaturized, ordered.isOnActiveSpace else { continue }
            return ordered === window
        }
        return false
    }

    /// Sends `onEvent` to Dart with [eventName] and [viewId].
    private func emitEvent(_ eventName: String, viewId: Int64) {
        channel?.invokeMethod(
            "onEvent",
            arguments: ["eventName": eventName, "viewId": Int(viewId)]
        )
    }

    private func viewIdForWindow(_ window: NSWindow) -> Int64? {
        windows.first(where: { $0.value === window })?.key
    }

    private func cgFloat(from value: Any?) -> CGFloat? {
        if let v = value as? CGFloat {
            return v
        }
        if let v = value as? NSNumber {
            return CGFloat(truncating: v)
        }
        if let v = value as? Double {
            return CGFloat(v)
        }
        if let v = value as? Int {
            return CGFloat(v)
        }
        return nil
    }

    private func int(from value: Any?) -> Int? {
        if let v = value as? Int {
            return v
        }
        if let v = value as? NSNumber {
            return v.intValue
        }
        return nil
    }

    private func int64(from args: [String: Any], key: String) -> Int64 {
        if let v = args[key] as? Int64 {
            return v
        }
        if let v = args[key] as? Int {
            return Int64(v)
        }
        if let v = args[key] as? NSNumber {
            return v.int64Value
        }
        return -1
    }
}
