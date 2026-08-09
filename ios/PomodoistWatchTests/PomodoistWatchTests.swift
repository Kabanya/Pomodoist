import XCTest
@testable import PomodoistWatch

final class PomodoistWatchTests: XCTestCase {
  func testDecodesSnapshot() throws {
    let snapshot = WatchSnapshot.decode(from: ["snapshot": sampleSnapshot()])

    XCTAssertEqual(snapshot?.focus.presetName, "Pomodoro")
    XCTAssertEqual(snapshot?.focus.preset?.workSeconds, 1500)
    XCTAssertEqual(snapshot?.tasks.today.first?.content, "Write")
    XCTAssertEqual(snapshot?.tasks.byProject["p1"]?.first?.content, "Write")
    XCTAssertEqual(snapshot?.projects.first?.openTaskCount, 3)

    let legacy = WatchSnapshot.decode(from: [
      "snapshot": sampleSnapshot(includeProjectTasks: false),
    ])
    XCTAssertEqual(legacy?.tasks.byProject, [:])
  }

  func testTimerMath() throws {
    let interval = WatchFocusInterval(
      id: "i1",
      type: "work",
      status: "running",
      plannedSeconds: 1500,
      startedAt: "2026-05-01T10:00:00Z",
      pausedAt: nil,
      pausedTotalSeconds: 60,
      sequenceNumber: 1
    )
    let now = try XCTUnwrap(WatchTimerMath.parseDate("2026-05-01T10:06:00Z"))

    XCTAssertEqual(WatchTimerMath.remainingSeconds(now: now, interval: interval), 1200)
    XCTAssertEqual(WatchTimerMath.progress(now: now, interval: interval), 0.2, accuracy: 0.001)
  }

  func testCommandPayloads() {
    XCTAssertEqual(WatchCommand.createQuickAdd("Buy milk")["type"] as? String, "task.createQuickAdd")
    XCTAssertNotNil(WatchCommand.createQuickAdd("Buy milk")["id"] as? String)
    XCTAssertEqual(WatchCommand.completeTask("t1")["taskId"] as? String, "t1")

    let taskFocus = WatchCommand.focusStartDefault(
      presetId: "classic",
      taskId: "t1",
      projectId: "p1",
      targetWorkIntervals: 3,
      replaceActive: true
    )
    XCTAssertEqual(taskFocus["presetId"] as? String, "classic")
    XCTAssertEqual(taskFocus["taskId"] as? String, "t1")
    XCTAssertEqual(taskFocus["projectId"] as? String, "p1")
    XCTAssertEqual(taskFocus["targetWorkIntervals"] as? Int, 3)
    XCTAssertEqual(taskFocus["replaceActive"] as? Bool, true)

    let restart = WatchCommand.focusRestartInterval()
    XCTAssertEqual(restart["type"] as? String, "focus.restartInterval")
    XCTAssertNotNil(restart["id"] as? String)
    XCTAssertNotNil(restart["createdAt"] as? String)
    XCTAssertNotNil(restart["occurredAt"] as? String)

    let transcriptCommand = WatchCommand.decomposeTranscript("Купить молоко", locale: "ru_RU")
    XCTAssertEqual(transcriptCommand["type"] as? String, "task.decomposeTranscript")
    XCTAssertEqual(transcriptCommand["transcript"] as? String, "Купить молоко")
    XCTAssertEqual(transcriptCommand["locale"] as? String, "ru_RU")
    XCTAssertNotNil(transcriptCommand["id"] as? String)

    let commit = WatchCommand.commitDrafts([
      WatchTaskDraft(quickAdd: "Write report", description: "Q2"),
    ])
    let tasks = commit["tasks"] as? [[String: Any]]
    XCTAssertEqual(tasks?.first?["quickAdd"] as? String, "Write report")
    XCTAssertEqual(tasks?.first?["description"] as? String, "Q2")
  }

  func testFocusProgressDisplay() {
    XCTAssertEqual(
      WatchFocusProgressDisplay.make(completed: 3, target: 5),
      .dots(completed: 3, target: 5)
    )
    XCTAssertEqual(
      WatchFocusProgressDisplay.make(completed: 3, target: 12),
      .fraction(completed: 3, target: 12)
    )
    XCTAssertEqual(
      WatchFocusProgressDisplay.make(completed: 10, target: 3),
      .dots(completed: 3, target: 3)
    )
  }

  func testTaskFocusAction() {
    XCTAssertEqual(
      WatchTaskFocusAction.resolve(focus: .empty, taskId: "task-1"),
      .start
    )

    var focus = WatchFocusSnapshot.empty
    focus.active = true
    focus.run = WatchFocusRun(
      id: "run-1",
      status: "active",
      taskId: "task-1",
      projectId: "project-1",
      startedAt: "2026-05-01T10:00:00Z",
      completedWorkIntervals: 0,
      targetWorkIntervals: 1
    )
    XCTAssertEqual(
      WatchTaskFocusAction.resolve(focus: focus, taskId: "task-1"),
      .showCurrent
    )
    XCTAssertEqual(
      WatchTaskFocusAction.resolve(focus: focus, taskId: "task-2"),
      .confirmReplacement
    )
  }

  @MainActor
  func testPersistsSnapshotAndPendingQueue() {
    let defaults = testDefaults("persist")
    let store = WatchCompanionStore(defaults: defaults, activateSession: false)

    store.send(WatchCommand.createQuickAdd("Buy milk"))

    let restored = WatchCompanionStore(defaults: defaults, activateSession: false)
    XCTAssertEqual(restored.pendingCommands.count, 1)
    XCTAssertEqual(restored.snapshot.tasks.recentAdded.first?.content, "Buy milk")
  }

  @MainActor
  func testOfflineFocusSurvivesRestart() throws {
    let defaults = testDefaults("focus")
    let start = try XCTUnwrap(WatchDateCoding.date(from: "2026-05-01T10:00:00Z"))
    let pause = try XCTUnwrap(WatchDateCoding.date(from: "2026-05-01T10:01:00Z"))
    let resume = try XCTUnwrap(WatchDateCoding.date(from: "2026-05-01T10:02:00Z"))
    let later = try XCTUnwrap(WatchDateCoding.date(from: "2026-05-01T10:03:00Z"))
    let store = WatchCompanionStore(defaults: defaults, activateSession: false)

    store.send(WatchCommand.focusStartDefault(now: start))
    store.send(WatchCommand.focusPause(now: pause))
    store.send(WatchCommand.focusResume(now: resume))

    let restored = WatchCompanionStore(defaults: defaults, activateSession: false)
    let interval = try XCTUnwrap(restored.snapshot.focus.interval)
    XCTAssertEqual(interval.pausedTotalSeconds, 60)
    XCTAssertEqual(WatchTimerMath.remainingSeconds(now: later, interval: interval), 1380)
  }

  @MainActor
  func testOfflineRestartFocusSurvivesRestart() throws {
    let defaults = testDefaults("restart")
    let start = try XCTUnwrap(WatchDateCoding.date(from: "2026-05-01T10:00:00Z"))
    let pause = try XCTUnwrap(WatchDateCoding.date(from: "2026-05-01T10:02:00Z"))
    let restart = try XCTUnwrap(WatchDateCoding.date(from: "2026-05-01T10:05:00Z"))
    let later = try XCTUnwrap(WatchDateCoding.date(from: "2026-05-01T10:06:00Z"))
    let store = WatchCompanionStore(defaults: defaults, activateSession: false)

    store.send(WatchCommand.focusStartDefault(now: start))
    store.send(WatchCommand.focusPause(now: pause))
    store.send(WatchCommand.focusRestartInterval(now: restart))

    let restored = WatchCompanionStore(defaults: defaults, activateSession: false)
    let interval = try XCTUnwrap(restored.snapshot.focus.interval)
    XCTAssertEqual(interval.status, "running")
    XCTAssertEqual(try XCTUnwrap(WatchDateCoding.date(from: interval.startedAt)), restart)
    XCTAssertNil(interval.pausedAt)
    XCTAssertEqual(interval.pausedTotalSeconds, 0)
    XCTAssertEqual(WatchTimerMath.remainingSeconds(now: later, interval: interval), 1440)
  }

  @MainActor
  func testAckedCommandClearsPendingQueue() {
    let defaults = testDefaults("ack")
    let store = WatchCompanionStore(defaults: defaults, activateSession: false)
    store.send(WatchCommand.createQuickAdd("Buy milk"))
    let id = store.pendingCommands[0].id

    store.receiveReply([
      "ok": true,
      "appliedCommandId": id,
      "snapshot": sampleSnapshot(appliedIds: [id]),
    ])

    XCTAssertTrue(store.pendingCommands.isEmpty)
  }

  @MainActor
  func testOlderSnapshotDoesNotRollbackOptimisticFocus() throws {
    let store = WatchCompanionStore(
      defaults: testDefaults("stale-snapshot"),
      activateSession: false
    )
    store.receiveReply([
      "ok": true,
      "snapshot": sampleSnapshot(
        generatedAt: "2026-05-01T10:00:00Z",
        focusActive: false
      ),
    ])
    let start = try XCTUnwrap(WatchDateCoding.date(from: "2026-05-01T10:01:00Z"))
    store.send(
      WatchCommand.focusStartDefault(
        presetId: "classic",
        taskId: "t1",
        projectId: "p1",
        targetWorkIntervals: 3,
        now: start
      )
    )

    store.receiveReply([
      "ok": true,
      "snapshot": sampleSnapshot(
        generatedAt: "2026-05-01T09:59:00Z",
        focusActive: false
      ),
    ])

    XCTAssertTrue(store.snapshot.focus.active)
    XCTAssertEqual(store.snapshot.focus.run?.taskId, "t1")
  }

  @MainActor
  func testNewSnapshotReplaysUnacknowledgedFocus() throws {
    let store = WatchCompanionStore(
      defaults: testDefaults("pending-replay"),
      activateSession: false
    )
    store.receiveReply([
      "ok": true,
      "snapshot": sampleSnapshot(
        generatedAt: "2026-05-01T10:00:00Z",
        focusActive: false
      ),
    ])
    let start = try XCTUnwrap(WatchDateCoding.date(from: "2026-05-01T10:01:00Z"))
    store.send(
      WatchCommand.focusStartDefault(
        presetId: "classic",
        taskId: "t1",
        projectId: "p1",
        targetWorkIntervals: 3,
        now: start
      )
    )

    store.receiveReply([
      "ok": true,
      "snapshot": sampleSnapshot(
        generatedAt: "2026-05-01T10:02:00Z",
        focusActive: false
      ),
    ])

    XCTAssertTrue(store.snapshot.focus.active)
    XCTAssertEqual(store.snapshot.focus.run?.taskId, "t1")
    XCTAssertEqual(store.snapshot.focus.run?.projectId, "p1")
    XCTAssertEqual(store.snapshot.focus.run?.targetWorkIntervals, 3)
  }

  @MainActor
  func testAcknowledgedFocusIsNotReplayed() throws {
    let store = WatchCompanionStore(
      defaults: testDefaults("acked-focus"),
      activateSession: false
    )
    store.receiveReply([
      "ok": true,
      "snapshot": sampleSnapshot(
        generatedAt: "2026-05-01T10:00:00Z",
        focusActive: false
      ),
    ])
    let start = try XCTUnwrap(WatchDateCoding.date(from: "2026-05-01T10:01:00Z"))
    store.send(WatchCommand.focusStartDefault(presetId: "classic", now: start))
    let commandId = try XCTUnwrap(store.pendingCommands.first?.id)

    store.receiveReply([
      "ok": true,
      "appliedCommandId": commandId,
      "snapshot": sampleSnapshot(
        generatedAt: "2026-05-01T10:02:00Z",
        focusActive: false,
        appliedIds: [commandId]
      ),
    ])

    XCTAssertTrue(store.pendingCommands.isEmpty)
    XCTAssertFalse(store.snapshot.focus.active)
  }

  @MainActor
  func testTaskFocusSurvivesRestart() throws {
    let defaults = testDefaults("task-focus")
    let store = WatchCompanionStore(defaults: defaults, activateSession: false)
    store.receiveReply([
      "ok": true,
      "snapshot": sampleSnapshot(
        generatedAt: "2026-05-01T10:00:00Z",
        focusActive: false
      ),
    ])
    let start = try XCTUnwrap(WatchDateCoding.date(from: "2026-05-01T10:01:00Z"))

    store.send(
      WatchCommand.focusStartDefault(
        presetId: "classic",
        taskId: "t1",
        projectId: "p1",
        targetWorkIntervals: 3,
        now: start
      )
    )

    let restored = WatchCompanionStore(defaults: defaults, activateSession: false)
    XCTAssertEqual(restored.snapshot.focus.presetId, "classic")
    XCTAssertEqual(restored.snapshot.focus.run?.taskId, "t1")
    XCTAssertEqual(restored.snapshot.focus.run?.projectId, "p1")
    XCTAssertEqual(restored.snapshot.focus.run?.targetWorkIntervals, 3)
  }

  @MainActor
  func testOpenIphoneMessageIsHidden() {
    let store = WatchCompanionStore(defaults: testDefaults("hidden-open-iphone"), activateSession: false)

    store.receiveReply(["ok": false, "conflict": true])
    XCTAssertNil(store.errorMessage)

    store.receiveReply(["ok": false, "error": "Open Pomodoist on iPhone"])
    XCTAssertNil(store.errorMessage)

    store.receiveReply(["ok": false, "error": "Network failed"])
    XCTAssertEqual(store.errorMessage, "Network failed")
  }
}

private func sampleSnapshot(
  generatedAt: String? = nil,
  focusActive: Bool = true,
  appliedIds: [String] = [],
  includeProjectTasks: Bool = true
) -> [String: Any] {
  var tasks: [String: Any] = [
    "today": [["id": "t1", "content": "Write", "projectId": "p1", "priority": 4, "completed": false, "estimatedFocusIntervals": 3, "completedFocusIntervals": 0]],
    "upcoming": [],
    "inbox": [],
    "recentAdded": [],
  ]
  if includeProjectTasks {
    tasks["byProject"] = [
      "p1": [["id": "t1", "content": "Write", "projectId": "p1", "priority": 4, "completed": false, "estimatedFocusIntervals": 3, "completedFocusIntervals": 0]],
    ]
  }
  var snapshot: [String: Any] = [
    "version": 1,
    "focus": focusActive ? [
      "active": true,
      "presetName": "Pomodoro",
      "preset": [
        "id": "classic",
        "name": "Pomodoro",
        "workSeconds": 1500,
        "shortBreakSeconds": 300,
        "longBreakSeconds": 900,
        "intervalsBeforeLongBreak": 4,
        "allowPause": true,
        "strictMode": false,
      ],
      "interval": [
        "id": "i1",
        "type": "work",
        "status": "running",
        "plannedSeconds": 1500,
        "startedAt": "2026-05-01T10:00:00Z",
        "pausedTotalSeconds": 0,
        "sequenceNumber": 1,
      ],
    ] : [
      "active": false,
      "presetId": "classic",
      "presetName": "Pomodoro",
      "preset": [
        "id": "classic",
        "name": "Pomodoro",
        "workSeconds": 1500,
        "shortBreakSeconds": 300,
        "longBreakSeconds": 900,
        "intervalsBeforeLongBreak": 4,
        "allowPause": true,
        "strictMode": false,
      ],
    ],
    "tasks": tasks,
    "projects": [["id": "p1", "name": "Work", "openTaskCount": 3]],
    "sync": ["appliedCommandIds": appliedIds],
  ]
  if let generatedAt {
    snapshot["generatedAt"] = generatedAt
  }
  return snapshot
}

private func testDefaults(_ name: String) -> UserDefaults {
  let suiteName = "PomodoistWatchTests.\(name).\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  return defaults
}
