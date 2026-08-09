import Foundation
import WatchConnectivity

@MainActor
final class WatchCompanionStore: NSObject, ObservableObject {
  @Published var snapshot = WatchSnapshot.empty
  @Published var errorMessage: String?
  @Published var messageIsError = false
  @Published var busy = false
  @Published var syncStatus = "Offline"
  @Published var selectedTab = 0
  @Published private(set) var pendingCommands = [WatchPendingCommand]()

  private let defaults: UserDefaults
  private let accountClient = WatchAccountClient()
  private let snapshotKey = "watch.snapshot.v1"
  private let pendingKey = "watch.pendingCommands.v1"
  private let deviceIdKey = "watch.deviceId.v1"
  private let maxPendingCommands = 100
  private var pollTimer: Timer?
  private var syncingPendingDirect = false

  init(defaults: UserDefaults = .standard, activateSession: Bool = true) {
    self.defaults = defaults
    super.init()
    restore()
    if activateSession {
      activate()
    }
    startPolling()
  }

  func send(
    _ command: [String: Any],
    queueIfOffline: Bool = true,
    completion: (([String: Any]) -> Void)? = nil
  ) {
    let prepared = WatchCommand.withMetadata(
      command,
      baseSnapshotGeneratedAt: snapshot.generatedAt
    )
    let canQueue = queueIfOffline && isOfflineCapable(prepared)
    if canQueue, !queue(prepared) {
      completion?(["ok": false])
      return
    }

    if accountClient.accountSession?.usable == true {
      busy = true
      showMessage("sync.syncing")
      Task { @MainActor in
        do {
          let reply = try await accountClient.send(command: prepared, deviceId: deviceId())
          busy = false
          syncStatus = "Synced"
          receiveReply(reply)
          completion?(reply)
        } catch {
          busy = false
          sendViaIphone(prepared, canQueue: canQueue, completion: completion)
        }
      }
      return
    }

    sendViaIphone(prepared, canQueue: canQueue, completion: completion)
  }

  private func sendViaIphone(
    _ prepared: [String: Any],
    canQueue: Bool,
    completion: (([String: Any]) -> Void)?
  ) {
    guard WCSession.isSupported() else {
      finishUnavailable(prepared, canQueue: canQueue, completion: completion)
      return
    }

    let session = WCSession.default
    guard session.activationState == .activated, session.isReachable else {
      finishUnavailable(prepared, canQueue: canQueue, completion: completion)
      return
    }

    busy = true
    showMessage("sync.syncing")
    session.sendMessage(prepared) { [weak self] reply in
      Task { @MainActor in
        self?.busy = false
        self?.receiveReply(reply)
        completion?(reply)
      }
    } errorHandler: { [weak self] _ in
      Task { @MainActor in
        self?.busy = false
        self?.finishUnavailable(prepared, canQueue: canQueue, completion: completion)
      }
    }
  }

  func requestSnapshot() {
    send(WatchCommand.snapshotRequest(), queueIfOffline: false)
  }

  func receiveReply(_ reply: [String: Any]) {
    let incomingSnapshot = WatchSnapshot.decode(from: reply)
    var appliedIds = incomingSnapshot?.sync.appliedCommandIds ?? []
    if let id = reply["appliedCommandId"] as? String {
      appliedIds.append(id)
    }
    removeApplied(appliedIds)
    if let incomingSnapshot {
      reconcileSnapshot(incomingSnapshot)
    }
    if let ok = reply["ok"] as? Bool, ok == false {
      if (reply["conflict"] as? Bool) == true {
        showMessage("sync.resolveOnIphone", isError: true)
      } else {
        showRawError(reply["error"] as? String)
      }
    } else {
      errorMessage = nil
      messageIsError = false
    }
    syncPendingCommands()
  }

  private func restore() {
    if let data = defaults.data(forKey: snapshotKey),
      let stored = try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    {
      snapshot = stored
    }
    if let data = defaults.data(forKey: pendingKey),
      let stored = try? JSONDecoder().decode([WatchPendingCommand].self, from: data)
    {
      pendingCommands = stored
    }
  }

  private func persistSnapshot() {
    if let data = try? JSONEncoder().encode(snapshot) {
      defaults.set(data, forKey: snapshotKey)
    }
  }

  private func persistPending() {
    if let data = try? JSONEncoder().encode(pendingCommands) {
      defaults.set(data, forKey: pendingKey)
    }
  }

  private func replaceSnapshot(_ snapshot: WatchSnapshot) {
    self.snapshot = snapshot
    persistSnapshot()
  }

  private func reconcileSnapshot(_ incoming: WatchSnapshot) {
    guard shouldAcceptSnapshot(incoming) else {
      return
    }
    var merged = incoming
    for pending in pendingCommands {
      applyOptimistic(pending.payload, to: &merged)
    }
    replaceSnapshot(merged)
  }

  private func shouldAcceptSnapshot(_ incoming: WatchSnapshot) -> Bool {
    guard let current = snapshot.generatedAt.flatMap(WatchDateCoding.date) else {
      return true
    }
    guard let candidate = incoming.generatedAt.flatMap(WatchDateCoding.date) else {
      return false
    }
    return candidate >= current
  }

  @discardableResult
  private func handleAccountSession(_ accountSession: WatchAccountSession) -> Bool {
    accountClient.updateSession(accountSession)
    if accountClient.accountSession?.usable == true {
      return true
    }
    if !accountSession.signedIn {
      replaceSnapshot(.empty)
      pendingCommands.removeAll()
      persistPending()
      errorMessage = nil
      messageIsError = false
      syncStatus = "Offline"
    }
    return false
  }

  private func shouldApplySnapshot(from context: [String: Any]) -> Bool {
    guard let accountSession = WatchAccountSession.decode(from: context["accountSession"]) else {
      return true
    }
    return accountSession.signedIn
  }

  private func queue(_ command: [String: Any]) -> Bool {
    guard let pending = WatchPendingCommand(command: command) else {
      showMessage("error.iphoneUnavailable", isError: true)
      return false
    }
    if pendingCommands.contains(where: { $0.id == pending.id }) {
      return true
    }
    guard pendingCommands.count < maxPendingCommands else {
      showMessage("sync.queueFull", isError: true)
      return false
    }
    pendingCommands.append(pending)
    persistPending()
    applyOptimistic(command)
    errorMessage = nil
    messageIsError = false
    return true
  }

  private func removeApplied(_ ids: [String]) {
    guard !ids.isEmpty else {
      return
    }
    let before = pendingCommands.count
    pendingCommands.removeAll { ids.contains($0.id) }
    if pendingCommands.count != before {
      persistPending()
    }
  }

  private func finishUnavailable(
    _ command: [String: Any],
    canQueue: Bool,
    completion: (([String: Any]) -> Void)?
  ) {
    if canQueue {
      syncPendingCommands()
      errorMessage = nil
      messageIsError = false
      syncStatus = "Queued"
      completion?(["ok": true, "queued": true])
    } else {
      showMessage("error.openIphone", isError: true)
      completion?(["ok": false])
    }
  }

  private func syncPendingCommands() {
    if accountClient.accountSession?.usable == true, !syncingPendingDirect {
      syncingPendingDirect = true
      Task { @MainActor in
        defer { syncingPendingDirect = false }
        for pending in pendingCommands {
          do {
            let reply = try await accountClient.send(command: pending.payload, deviceId: deviceId())
            receiveReply(reply)
          } catch {
            break
          }
        }
      }
    }
    guard WCSession.isSupported() else {
      return
    }
    let session = WCSession.default
    guard session.activationState == .activated else {
      return
    }
    for pending in pendingCommands {
      session.transferUserInfo(["command": pending.payload])
    }
  }

  private func activate() {
    guard WCSession.isSupported() else {
      return
    }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  private func startPolling() {
    pollTimer?.invalidate()
    pollTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard self?.accountClient.accountSession?.usable == true else {
          return
        }
        self?.requestSnapshot()
      }
    }
  }

  private func deviceId() -> String {
    if let existing = defaults.string(forKey: deviceIdKey), !existing.isEmpty {
      return existing
    }
    let id = "watch-\(UUID().uuidString)"
    defaults.set(id, forKey: deviceIdKey)
    return id
  }

  private func showMessage(_ key: String, isError: Bool = false) {
    if key == "error.openIphone" || key == "sync.resolveOnIphone" {
      errorMessage = nil
      messageIsError = false
      return
    }
    errorMessage = String(localized: String.LocalizationValue(key))
    messageIsError = isError
  }

  private func showRawError(_ value: String?) {
    if value?.localizedCaseInsensitiveContains("Open Pomodoist on iPhone") == true {
      errorMessage = nil
      messageIsError = false
      return
    }
    errorMessage = value ?? String(localized: "error.iphoneUnavailable")
    messageIsError = true
  }

  private func isOfflineCapable(_ command: [String: Any]) -> Bool {
    switch command["type"] as? String {
    case "task.createQuickAdd",
      "task.commitDrafts",
      "task.complete",
      "task.uncomplete",
      "focus.startDefault",
      "focus.pause",
      "focus.resume",
      "focus.restartInterval",
      "focus.complete",
      "focus.skip",
      "focus.stop":
      return true
    default:
      return false
    }
  }

  private func applyOptimistic(_ command: [String: Any]) {
    var updated = snapshot
    applyOptimistic(command, to: &updated)
    snapshot = updated
    persistSnapshot()
  }

  private func applyOptimistic(
    _ command: [String: Any],
    to snapshot: inout WatchSnapshot
  ) {
    switch command["type"] as? String {
    case "task.createQuickAdd":
      if let input = command["input"] as? String {
        addOptimisticTask(input, command: command, to: &snapshot)
      }
    case "task.commitDrafts":
      for draft in command["tasks"] as? [[String: Any]] ?? [] {
        if let quickAdd = draft["quickAdd"] as? String {
          addOptimisticTask(quickAdd, command: command, to: &snapshot)
        }
      }
    case "task.complete":
      if let id = (command["taskId"] as? String) ?? (command["id"] as? String) {
        updateTask(id: id, completed: true, in: &snapshot)
      }
    case "task.uncomplete":
      if let id = (command["taskId"] as? String) ?? (command["id"] as? String) {
        updateTask(id: id, completed: false, in: &snapshot)
      }
    case "focus.startDefault":
      startOptimisticFocus(command, in: &snapshot)
    case "focus.pause":
      pauseOptimisticFocus(command, in: &snapshot)
    case "focus.resume":
      resumeOptimisticFocus(command, in: &snapshot)
    case "focus.restartInterval":
      restartOptimisticFocus(command, in: &snapshot)
    case "focus.complete":
      completeOptimisticFocus(command, in: &snapshot)
    case "focus.skip", "focus.stop":
      clearOptimisticFocus(in: &snapshot)
    default:
      break
    }
  }

  private func addOptimisticTask(
    _ input: String,
    command: [String: Any],
    to snapshot: inout WatchSnapshot
  ) {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let commandId = command["id"] as? String else {
      return
    }
    let task = WatchTask(
      id: "watch-\(commandId)",
      content: trimmed,
      description: nil,
      projectId: "inbox",
      priority: 4,
      completed: false,
      schedule: nil,
      estimatedFocusIntervals: nil,
      completedFocusIntervals: 0,
      createdAt: command["occurredAt"] as? String
    )
    upsert(task, in: &snapshot.tasks.inbox)
    upsert(task, in: &snapshot.tasks.recentAdded)
  }

  private func upsert(_ task: WatchTask, in tasks: inout [WatchTask]) {
    tasks.removeAll { $0.id == task.id }
    tasks.insert(task, at: 0)
    if tasks.count > 12 {
      tasks.removeLast(tasks.count - 12)
    }
  }

  private func updateTask(
    id: String,
    completed: Bool,
    in snapshot: inout WatchSnapshot
  ) {
    updateTask(id: id, completed: completed, in: &snapshot.tasks.today)
    updateTask(id: id, completed: completed, in: &snapshot.tasks.upcoming)
    updateTask(id: id, completed: completed, in: &snapshot.tasks.inbox)
    updateTask(id: id, completed: completed, in: &snapshot.tasks.recentAdded)
    for projectId in Array(snapshot.tasks.byProject.keys) {
      updateTask(
        id: id,
        completed: completed,
        in: &snapshot.tasks.byProject[projectId, default: []]
      )
    }
  }

  private func updateTask(id: String, completed: Bool, in tasks: inout [WatchTask]) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else {
      return
    }
    tasks[index].completed = completed
  }

  private func startOptimisticFocus(
    _ command: [String: Any],
    in snapshot: inout WatchSnapshot
  ) {
    guard let commandId = command["id"] as? String else {
      return
    }
    if snapshot.focus.active, command["replaceActive"] as? Bool != true {
      return
    }
    let occurredAt = command["occurredAt"] as? String ?? WatchDateCoding.string(from: Date())
    let preset = snapshot.focus.preset
    let taskId = command["taskId"] as? String
    let presetId = (command["presetId"] as? String) ?? preset?.id ?? snapshot.focus.presetId ?? "default"
    let presetName = preset?.name ?? snapshot.focus.presetName ?? "Pomodoro"
    let plannedSeconds = preset?.workSeconds ?? 25 * 60
    let defaultTarget = taskId == nil ? (preset?.intervalsBeforeLongBreak ?? 1) : 1
    let targetWorkIntervals = max(
      1,
      (command["targetWorkIntervals"] as? Int) ?? defaultTarget
    )
    snapshot.focus.active = true
    snapshot.focus.presetId = presetId
    snapshot.focus.presetName = presetName
    snapshot.focus.run = WatchFocusRun(
      id: "watch-run-\(commandId)",
      status: "active",
      taskId: taskId,
      projectId: command["projectId"] as? String,
      startedAt: occurredAt,
      completedWorkIntervals: 0,
      targetWorkIntervals: targetWorkIntervals
    )
    snapshot.focus.interval = WatchFocusInterval(
      id: "watch-interval-\(commandId)",
      type: "work",
      status: "running",
      plannedSeconds: plannedSeconds,
      startedAt: occurredAt,
      pausedAt: nil,
      pausedTotalSeconds: 0,
      sequenceNumber: 1
    )
  }

  private func pauseOptimisticFocus(
    _ command: [String: Any],
    in snapshot: inout WatchSnapshot
  ) {
    guard snapshot.focus.interval?.status == "running" else {
      return
    }
    let occurredAt = command["occurredAt"] as? String ?? WatchDateCoding.string(from: Date())
    snapshot.focus.interval?.status = "paused"
    snapshot.focus.interval?.pausedAt = occurredAt
    snapshot.focus.run?.status = "paused"
  }

  private func resumeOptimisticFocus(
    _ command: [String: Any],
    in snapshot: inout WatchSnapshot
  ) {
    guard var interval = snapshot.focus.interval, interval.status == "paused" else {
      return
    }
    let occurredAt = command["occurredAt"] as? String ?? WatchDateCoding.string(from: Date())
    if let pausedAt = interval.pausedAt.flatMap(WatchDateCoding.date),
      let resumedAt = WatchDateCoding.date(from: occurredAt)
    {
      interval.pausedTotalSeconds += max(0, Int(resumedAt.timeIntervalSince(pausedAt)))
    }
    interval.status = "running"
    interval.pausedAt = nil
    snapshot.focus.interval = interval
    snapshot.focus.run?.status = "active"
  }

  private func restartOptimisticFocus(
    _ command: [String: Any],
    in snapshot: inout WatchSnapshot
  ) {
    guard var interval = snapshot.focus.interval else {
      return
    }
    let occurredAt = command["occurredAt"] as? String ?? WatchDateCoding.string(from: Date())
    interval.status = "running"
    interval.startedAt = occurredAt
    interval.pausedAt = nil
    interval.pausedTotalSeconds = 0
    snapshot.focus.interval = interval
    snapshot.focus.active = true
    snapshot.focus.run?.status = "active"
  }

  private func completeOptimisticFocus(
    _ command: [String: Any],
    in snapshot: inout WatchSnapshot
  ) {
    guard var interval = snapshot.focus.interval, var run = snapshot.focus.run else {
      return
    }
    let occurredAt = command["occurredAt"] as? String ?? WatchDateCoding.string(from: Date())
    if interval.type == "work" {
      run.completedWorkIntervals += 1
    }
    if run.completedWorkIntervals >= run.targetWorkIntervals {
      clearOptimisticFocus(in: &snapshot)
      return
    }
    let preset = snapshot.focus.preset
    let nextIsBreak = interval.type == "work"
    let nextType = nextIsBreak ? "shortBreak" : "work"
    let plannedSeconds = nextIsBreak ? (preset?.shortBreakSeconds ?? 5 * 60) : (preset?.workSeconds ?? 25 * 60)
    run.status = "active"
    interval = WatchFocusInterval(
      id: "watch-interval-\(command["id"] as? String ?? UUID().uuidString)-next",
      type: nextType,
      status: "running",
      plannedSeconds: plannedSeconds,
      startedAt: occurredAt,
      pausedAt: nil,
      pausedTotalSeconds: 0,
      sequenceNumber: interval.sequenceNumber + 1
    )
    snapshot.focus.active = true
    snapshot.focus.run = run
    snapshot.focus.interval = interval
  }

  private func clearOptimisticFocus(in snapshot: inout WatchSnapshot) {
    snapshot.focus.active = false
    snapshot.focus.run = nil
    snapshot.focus.interval = nil
  }
}

extension WatchCompanionStore: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    Task { @MainActor in
      var directAccountAvailable = self.accountClient.accountSession?.usable == true
      if let accountSession = WatchAccountSession.decode(from: session.receivedApplicationContext["accountSession"]) {
        directAccountAvailable = self.handleAccountSession(accountSession)
      }
      if !directAccountAvailable,
        self.shouldApplySnapshot(from: session.receivedApplicationContext),
        let snapshot = WatchSnapshot.decode(from: session.receivedApplicationContext)
      {
        self.removeApplied(snapshot.sync.appliedCommandIds)
        self.reconcileSnapshot(snapshot)
      }
      if activationState == .activated,
        self.shouldApplySnapshot(from: session.receivedApplicationContext)
      {
        self.requestSnapshot()
        self.syncPendingCommands()
      }
    }
  }

  nonisolated func session(
    _ session: WCSession,
    didReceiveApplicationContext applicationContext: [String: Any]
  ) {
    Task { @MainActor in
      var directAccountAvailable = self.accountClient.accountSession?.usable == true
      if let accountSession = WatchAccountSession.decode(from: applicationContext["accountSession"]) {
        directAccountAvailable = self.handleAccountSession(accountSession)
      }
      if directAccountAvailable {
        self.requestSnapshot()
      } else if self.shouldApplySnapshot(from: applicationContext),
        let snapshot = WatchSnapshot.decode(from: applicationContext)
      {
        self.removeApplied(snapshot.sync.appliedCommandIds)
        self.reconcileSnapshot(snapshot)
        self.errorMessage = nil
        self.messageIsError = false
      }
    }
  }
}
