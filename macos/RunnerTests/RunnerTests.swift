import Cocoa
import Carbon.HIToolbox
import FlutterMacOS
import XCTest

class RunnerTests: XCTestCase {

  func testQuickAddGlobalShortcutDefaultsAndRoundTrips() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let expected = QuickAddGlobalShortcut.default

    XCTAssertEqual(QuickAddGlobalShortcut.load(from: defaults), expected)
    XCTAssertEqual(
      QuickAddGlobalShortcut(dictionary: expected.dictionary),
      expected
    )
    XCTAssertEqual(expected.displayLabel, "⌥Space")
  }

  func testFailedQuickAddShortcutRegistrationKeepsStoredBinding() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let viewController = FlutterViewController()
    let channel = FlutterMethodChannel(
      name: UUID().uuidString,
      binaryMessenger: viewController.engine.binaryMessenger
    )
    let controller = QuickAddHotKeyController(channel: channel, defaults: defaults)
    let candidate = QuickAddGlobalShortcut(
      keyCode: UInt32(kVK_ANSI_J),
      modifiers: UInt32(cmdKey),
      keyLabel: "J"
    )
    var attempts: [QuickAddGlobalShortcut] = []

    let status = controller.applyShortcut(candidate) { shortcut in
      attempts.append(shortcut)
      return shortcut == candidate ? OSStatus(-1) : noErr
    }

    XCTAssertEqual(status, OSStatus(-1))
    XCTAssertEqual(attempts, [candidate, .default])
    XCTAssertEqual(controller.currentShortcut, .default)
    XCTAssertEqual(QuickAddGlobalShortcut.load(from: defaults), .default)
  }

  func testSuccessfulQuickAddShortcutRegistrationPersistsBinding() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let viewController = FlutterViewController()
    let channel = FlutterMethodChannel(
      name: UUID().uuidString,
      binaryMessenger: viewController.engine.binaryMessenger
    )
    let controller = QuickAddHotKeyController(channel: channel, defaults: defaults)
    let candidate = QuickAddGlobalShortcut(
      keyCode: UInt32(kVK_ANSI_J),
      modifiers: UInt32(cmdKey | shiftKey),
      keyLabel: "J"
    )

    XCTAssertEqual(controller.applyShortcut(candidate) { _ in noErr }, noErr)
    XCTAssertEqual(controller.currentShortcut, candidate)
    XCTAssertEqual(QuickAddGlobalShortcut.load(from: defaults), candidate)
  }

  func testDisablingQuickAddUnregistersTheHotKey() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let viewController = FlutterViewController()
    let channel = FlutterMethodChannel(
      name: UUID().uuidString,
      binaryMessenger: viewController.engine.binaryMessenger
    )
    let controller = QuickAddHotKeyController(channel: channel, defaults: defaults)
    var unregisterCount = 0

    XCTAssertEqual(
      controller.applyEnabled(false) {
        unregisterCount += 1
        return noErr
      },
      noErr
    )
    XCTAssertFalse(controller.isEnabled)
    XCTAssertEqual(unregisterCount, 1)
  }

  func testResolvesFlutterControllerFromApplicationWindows() {
    let expected = FlutterViewController()
    let window = NSWindow()
    window.contentViewController = expected

    XCTAssertTrue(
      resolveFlutterViewController(mainWindow: nil, windows: [window]) === expected
    )
  }

  func testDecodesFocusSnapshot() {
    let snapshot = PomodoistSnapshot.decode(from: [
      "version": 1,
      "generatedAt": "2026-07-09T12:00:00.000Z",
      "focus": [
        "active": false,
        "presetId": "deep-work",
        "presetName": "Deep Work",
        "preset": [
          "id": "deep-work",
          "name": "Deep Work",
          "workSeconds": 50 * 60,
          "shortBreakSeconds": 10 * 60,
          "longBreakSeconds": 25 * 60,
          "intervalsBeforeLongBreak": 4,
          "allowPause": true,
          "strictMode": false,
        ],
      ],
      "tasks": [:],
      "projects": [],
      "sync": [:],
    ])

    XCTAssertEqual(snapshot?.focus.presetName, "Deep Work")
    XCTAssertEqual(snapshot?.focus.preset?.workSeconds, 50 * 60)
    XCTAssertEqual(
      PomodoistFocusDisplay.title(
        now: Date(timeIntervalSince1970: 0),
        focus: snapshot?.focus ?? .empty
      ),
      "\u{25EF} 50:00"
    )
  }

  func testSnapshotStoreReadsSharedFileWithoutDefaultsCache() {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let store = PomodoistFocusSnapshotStore(defaults: defaults, fileURL: fileURL)

    store.save(dictionary: [
      "version": 1,
      "focus": [
        "active": false,
        "presetId": "classic",
        "presetName": "Classic",
        "preset": [
          "id": "classic",
          "name": "Classic",
          "workSeconds": 25 * 60,
          "shortBreakSeconds": 5 * 60,
          "longBreakSeconds": 15 * 60,
          "intervalsBeforeLongBreak": 4,
          "allowPause": true,
          "strictMode": false,
        ],
      ],
    ])
    defaults.removeObject(forKey: pomodoistFocusSnapshotDefaultsKey)

    XCTAssertEqual(store.load().focus.presetName, "Classic")
  }

  func testRemainingTimeUsesRunningClock() {
    let now = date("2026-07-09T12:08:00.000Z")
    let interval = interval(
      type: "work",
      status: "running",
      plannedSeconds: 25 * 60,
      startedAt: "2026-07-09T12:00:00.000Z",
      pausedTotalSeconds: 60
    )

    XCTAssertEqual(
      PomodoistFocusDisplay.remainingSeconds(now: now, interval: interval),
      18 * 60
    )
  }

  func testStatusTitleFormattingForFocusStates() {
    let now = date("2026-07-09T12:20:00.000Z")

    XCTAssertEqual(
      PomodoistFocusDisplay.title(now: now, focus: idleFocus(workSeconds: 25 * 60)),
      "\u{25EF} 25:00"
    )
    XCTAssertEqual(
      PomodoistFocusDisplay.title(
        now: now,
        focus: activeFocus(
          interval: interval(
            type: "work",
            status: "running",
            plannedSeconds: 25 * 60,
            startedAt: "2026-07-09T12:00:00.000Z"
          )
        )
      ),
      "\u{25EF} 05:00"
    )
    XCTAssertEqual(
      PomodoistFocusDisplay.title(
        now: now,
        focus: activeFocus(
          interval: interval(
            type: "work",
            status: "paused",
            plannedSeconds: 25 * 60,
            startedAt: "2026-07-09T12:00:00.000Z",
            pausedAt: "2026-07-09T12:04:00.000Z"
          )
        )
      ),
      "\u{25EF} 21:00"
    )
    XCTAssertEqual(
      PomodoistFocusDisplay.title(
        now: now,
        focus: activeFocus(
          interval: interval(
            type: "shortBreak",
            status: "running",
            plannedSeconds: 5 * 60,
            startedAt: "2026-07-09T12:17:00.000Z"
          )
        )
      ),
      "\u{25EF} 02:00"
    )
  }

  func testUsesProductionAppGroupIdentifier() {
    XCTAssertEqual(pomodoistFocusAppGroupIdentifier, "group.com.pomodoist")
  }

  func testTimerColorPresetsMatchMenuContract() {
    XCTAssertEqual(
      PomodoistTimerColor.allCases.map(\.rawValue),
      ["white", "black", "red", "green", "blue", "orange", "purple"]
    )
  }

  func testCompleteCommandMatchesCompanionContract() {
    XCTAssertEqual(PomodoistFocusCommand.complete, "focus.complete")
  }

  func testStartCommandIsOnlyAvailableWhenItCanSucceed() {
    let running = activeFocus(
      interval: interval(
        type: "work",
        status: "running",
        plannedSeconds: 25 * 60,
        startedAt: "2026-07-09T12:00:00.000Z"
      )
    )
    let paused = activeFocus(
      interval: interval(
        type: "work",
        status: "paused",
        plannedSeconds: 25 * 60,
        startedAt: "2026-07-09T12:00:00.000Z",
        pausedAt: "2026-07-09T12:05:00.000Z"
      )
    )
    let ready = activeFocus(
      interval: interval(
        type: "shortBreak",
        status: "ready",
        plannedSeconds: 5 * 60,
        startedAt: "2026-07-09T12:25:00.000Z"
      )
    )

    XCTAssertEqual(
      PomodoistFocusDisplay.primaryStartCommand(focus: idleFocus(workSeconds: 25 * 60)),
      PomodoistFocusCommand.startDefault
    )
    XCTAssertNil(PomodoistFocusDisplay.primaryStartCommand(focus: running))
    XCTAssertNil(PomodoistFocusDisplay.primaryStartCommand(focus: paused))
    XCTAssertEqual(
      PomodoistFocusDisplay.primaryStartCommand(focus: ready),
      PomodoistFocusCommand.restartInterval
    )
  }

  func testRunningWidgetTimelineAdvancesProgressEachMinute() {
    let now = date("2026-07-09T12:00:00.000Z")
    let focus = activeFocus(
      interval: interval(
        type: "work",
        status: "running",
        plannedSeconds: 3 * 60,
        startedAt: "2026-07-09T12:00:00.000Z"
      )
    )

    XCTAssertEqual(
      PomodoistFocusDisplay.timelineDates(now: now, focus: focus),
      [
        now,
        now.addingTimeInterval(60),
        now.addingTimeInterval(120),
        now.addingTimeInterval(180),
      ]
    )
    XCTAssertEqual(
      PomodoistFocusDisplay.timelineDates(
        now: now,
        focus: idleFocus(workSeconds: 25 * 60)
      ),
      [now]
    )
  }

  private func idleFocus(workSeconds: Int) -> PomodoistFocusSnapshot {
    PomodoistFocusSnapshot(
      active: false,
      presetId: "classic",
      presetName: "Classic",
      preset: preset(workSeconds: workSeconds),
      run: nil,
      interval: nil
    )
  }

  private func activeFocus(interval: PomodoistFocusInterval) -> PomodoistFocusSnapshot {
    PomodoistFocusSnapshot(
      active: true,
      presetId: "classic",
      presetName: "Classic",
      preset: preset(workSeconds: 25 * 60),
      run: PomodoistFocusRun(
        id: "run-1",
        status: interval.status == "paused" ? "paused" : "active",
        taskId: nil,
        projectId: nil,
        startedAt: interval.startedAt,
        completedWorkIntervals: 1,
        targetWorkIntervals: 4
      ),
      interval: interval
    )
  }

  private func preset(workSeconds: Int) -> PomodoistFocusPreset {
    PomodoistFocusPreset(
      id: "classic",
      name: "Classic",
      workSeconds: workSeconds,
      shortBreakSeconds: 5 * 60,
      longBreakSeconds: 15 * 60,
      intervalsBeforeLongBreak: 4,
      allowPause: true,
      strictMode: false
    )
  }

  private func interval(
    type: String,
    status: String,
    plannedSeconds: Int,
    startedAt: String,
    pausedAt: String? = nil,
    pausedTotalSeconds: Int = 0
  ) -> PomodoistFocusInterval {
    PomodoistFocusInterval(
      id: "interval-1",
      type: type,
      status: status,
      plannedSeconds: plannedSeconds,
      startedAt: startedAt,
      pausedAt: pausedAt,
      pausedTotalSeconds: pausedTotalSeconds,
      sequenceNumber: 1
    )
  }

  private func date(_ value: String) -> Date {
    PomodoistDateCoding.date(from: value) ?? Date(timeIntervalSince1970: 0)
  }
}
