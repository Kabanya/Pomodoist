import Flutter
import WatchConnectivity
import WidgetKit
import ActivityKit
import UIKit

func focusSnapshotDictionary(from context: [String: Any]) -> [String: Any] {
  (context["snapshot"] as? [String: Any]) ?? context
}

final class WatchCompanionHost: NSObject, WCSessionDelegate {
  static let shared = WatchCompanionHost()

  private var channel: FlutterMethodChannel?
  private var latestSnapshot: [String: Any]?
  private var latestContext: [String: Any]?
  private let focusSnapshotStore = PomodoistFocusSnapshotStore()
  private var activityUpdate: Task<Void, Never>?

  @MainActor
  func configure(with engineBridge: FlutterImplicitEngineBridge) {
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WatchCompanionHost") else {
      return
    }
    channel = FlutterMethodChannel(
      name: "pomodoist/watch_companion",
      binaryMessenger: registrar.messenger()
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handleFlutterCall(call, result: result)
    }
    PomodoistWidgetCommands.handler = { [weak self] command, reply in
      guard let self else { reply(["ok": false]); return }
      self.forwardCommandToFlutter(command, replyHandler: reply)
    }
    NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive),
      name: UIApplication.didBecomeActiveNotification, object: nil)
    activateSession()
  }

  @objc private func didBecomeActive() {
    forwardCommandToFlutter(PomodoistFocusCommand.make(type: PomodoistFocusCommand.snapshotRequest), replyHandler: nil)
  }

  private func activateSession() {
    guard WCSession.isSupported() else {
      return
    }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  private func handleFlutterCall(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "updateSnapshot":
      guard let context = sanitizeDictionary(call.arguments) else {
        result(
          FlutterError(
            code: "invalid_snapshot",
            message: "Expected a property-list compatible watch context",
            details: nil
          )
        )
        return
      }
      let snapshot = focusSnapshotDictionary(from: context)
      guard PomodoistSnapshot.decode(from: snapshot) != nil else {
        result(
          FlutterError(
            code: "invalid_snapshot",
            message: "Expected a valid focus snapshot",
            details: nil
          )
        )
        return
      }
      latestSnapshot = snapshot
      latestContext = context["snapshot"] == nil ? ["snapshot": snapshot] : context
      focusSnapshotStore.save(dictionary: snapshot)
      if #available(iOS 14.0, *) {
        WidgetCenter.shared.reloadAllTimelines()
      }
      updateLiveActivity(snapshot)
      updateWatchContext(latestContext ?? ["snapshot": snapshot])
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func updateWatchContext(_ context: [String: Any]) {
    guard WCSession.isSupported() else {
      return
    }
    let session = WCSession.default
    guard session.activationState == .activated else {
      return
    }
    do {
      try session.updateApplicationContext(context)
    } catch {
      // Companion sync is best-effort; command replies still return snapshots.
    }
  }

  private func sendCommandToFlutter(
    _ command: [String: Any],
    replyHandler: (([String: Any]) -> Void)?
  ) {
    forwardCommandToFlutter(command, replyHandler: replyHandler)
  }

  private func forwardCommandToFlutter(
    _ command: [String: Any],
    replyHandler: (([String: Any]) -> Void)?
  ) {
    guard let channel else {
      var reply: [String: Any] = [
        "ok": false,
        "error": "Open Pomodoist on iPhone",
      ]
      if let latestSnapshot {
        reply["snapshot"] = latestSnapshot
      }
      replyHandler?(reply)
      return
    }
    channel.invokeMethod("command", arguments: command) { [weak self] response in
      let reply = sanitizeDictionary(response) ?? [
        "ok": false,
        "error": "Invalid Flutter response",
      ]
      self?.handleCommandReply(reply)
      replyHandler?(reply)
    }
  }

  private func handleCommandReply(_ reply: [String: Any]) {
    guard let snapshot = reply["snapshot"] as? [String: Any] else {
      return
    }
    latestSnapshot = snapshot
    var context = latestContext ?? [:]
    context["snapshot"] = snapshot
    latestContext = context
    focusSnapshotStore.save(dictionary: snapshot)
    WidgetCenter.shared.reloadAllTimelines()
    updateLiveActivity(snapshot)
    updateWatchContext(context)
  }

  private func updateLiveActivity(_ dictionary: [String: Any]) {
    guard #available(iOS 16.2, *), let snapshot = PomodoistSnapshot.decode(from: dictionary) else { return }
    let previous = activityUpdate
    activityUpdate = Task { @MainActor in
      await previous?.value
      let state = PomodoistFocusActivityAttributes.ContentState(snapshot: snapshot, now: Date())
      var current: Activity<PomodoistFocusActivityAttributes>?
      for activity in Activity<PomodoistFocusActivityAttributes>.activities {
        if state != nil, activity.attributes.runID == snapshot.focus.run?.id {
          current = activity
        } else {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
      }
      guard let state, let runID = snapshot.focus.run?.id else { return }
      let content = ActivityContent(state: state, staleDate: state.end)
      if let current {
        await current.update(content)
      } else if UIApplication.shared.applicationState == .active,
        ActivityAuthorizationInfo().areActivitiesEnabled
      {
        do {
          _ = try Activity.request(attributes: PomodoistFocusActivityAttributes(runID: runID), content: content, pushType: nil)
        } catch {
          NSLog("Pomodoist Live Activity request failed: %ld", (error as NSError).code)
        }
      }
    }
  }

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    if activationState == .activated, let latestContext {
      updateWatchContext(latestContext)
    }
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    sendCommandToFlutter(message, replyHandler: replyHandler)
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    sendCommandToFlutter(message, replyHandler: nil)
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    let command = (userInfo["command"] as? [String: Any]) ?? userInfo
    sendCommandToFlutter(command, replyHandler: nil)
  }
}

private func sanitizeDictionary(_ value: Any?) -> [String: Any]? {
  guard let dictionary = value as? [String: Any] else {
    return nil
  }
  var clean = [String: Any]()
  for (key, value) in dictionary {
    if let sanitized = sanitizePropertyListValue(value) {
      clean[key] = sanitized
    }
  }
  return clean
}

private func sanitizePropertyListValue(_ value: Any?) -> Any? {
  switch value {
  case nil:
    return nil
  case is NSNull:
    return nil
  case let value as String:
    return value
  case let value as NSNumber:
    return value
  case let value as Date:
    return value
  case let value as Data:
    return value
  case let value as [Any]:
    return value.compactMap(sanitizePropertyListValue)
  case let value as [String: Any]:
    return sanitizeDictionary(value)
  default:
    return String(describing: value!)
  }
}
