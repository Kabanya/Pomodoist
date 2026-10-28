import Foundation
import ImageIO

@main
struct AppleWidgetSnapshotCheck {
  static func main() throws {
    let legacy: [String: Any] = ["version": 1, "focus": ["active": false]]
    let empty = PomodoistSnapshot.decode(from: legacy)
    precondition(empty != nil && empty?.widgets == nil)
    var snapshot = empty!
    snapshot.widgets = PomodoistWidgetSnapshot(day: "2026-05-01", focusTaskTitle: "Private task",
      tasks: [PomodoistWidgetTask(id: "a/b?x=1&y=2", title: "Design review", start: nil)],
      agenda: [], habits: [], totalHabits: 0, completedHabits: 0, completedTasks: 8,
      week: [PomodoistWidgetDay(day: "2026-05-01", focusSeconds: 120),
        PomodoistWidgetDay(day: "2026-05-02", focusSeconds: -60)])
    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(PomodoistSnapshot.self, from: data)
    precondition(decoded == snapshot)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 11 * 3600)!
    let sameDay = PomodoistDateCoding.date(from: "2026-04-30T13:01:00Z")!
    let nextDay = PomodoistDateCoding.date(from: "2026-05-01T13:00:00Z")!
    precondition(snapshot.widgets!.isCurrent(on: sameDay, calendar: calendar))
    precondition(!snapshot.widgets!.isCurrent(on: nextDay, calendar: calendar))
    precondition(snapshot.widgets!.focusSeconds == 120)
    precondition(snapshot.widgets!.week.first!.date != nil)
    let url = pomodoistWidgetURL(screen: "tasks", taskID: "a/b?x=1&y=2")!
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
    precondition(query.count == 2 && query.last!.value == "a/b?x=1&y=2")
    precondition(!String(decoding: data, as: UTF8.self).contains("accountSession"))
    let suite = "apple-widget-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: file)
    }
    let store = PomodoistFocusSnapshotStore(defaults: defaults, fileURL: file)
    var dictionary = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    dictionary["accountSession"] = ["accessToken": "test-token"]
    store.save(dictionary: dictionary)
    precondition(store.load() == snapshot)
    let stored = try Data(contentsOf: file)
    precondition(!String(decoding: stored, as: UTF8.self).contains("test-token"))
    defaults.removeObject(forKey: pomodoistFocusSnapshotDefaultsKey)
    precondition(store.load() == snapshot)
    var focus = PomodoistFocusSnapshot.empty
    precondition(PomodoistWidgetPomoState(focus: focus).pose == .calm)
    focus.active = true
    focus.run = PomodoistFocusRun(id: "run", status: "active", taskId: nil,
      projectId: nil, startedAt: "2026-05-01T00:00:00Z", completedWorkIntervals: 0, targetWorkIntervals: 4)
    focus.interval = PomodoistFocusInterval(id: "interval", type: "work", status: "running",
      plannedSeconds: 1500, startedAt: "2026-05-01T00:00:00Z", pausedAt: nil,
      pausedTotalSeconds: 0, sequenceNumber: 1)
    let working = PomodoistWidgetPomoState(focus: focus)
    precondition(working.pose == .focus)
    focus.interval!.status = "paused"
    precondition(PomodoistWidgetPomoState(focus: focus).pose == .calm)
    precondition(PomodoistWidgetPomoState(focus: focus) != working)
    focus.interval!.status = "running"
    focus.interval!.type = "short_break"
    precondition(PomodoistWidgetPomoState(focus: focus).pose == .rest)
    var overview = snapshot.widgets!
    let tasks = PomodoistWidgetPomoState(kind: .tasks, data: overview)
    overview.focusTaskTitle = "Edited title"
    overview.week[0].focusSeconds += 60
    precondition(PomodoistWidgetPomoState(kind: .tasks, data: overview) == tasks)
    overview.completedTasks += 1
    precondition(PomodoistWidgetPomoState(kind: .tasks, data: overview) != tasks)
    overview.tasks = []
    precondition(PomodoistWidgetPomoState(kind: .tasks, data: overview).pose == .happy)
    precondition(PomodoistWidgetPomoState(kind: .habits, data: overview).pose == .calm)
    overview.totalHabits = 2
    overview.completedHabits = 2
    precondition(PomodoistWidgetPomoState(kind: .habits, data: overview).pose == .happy)
    precondition(PomodoistWidgetPomoState(kind: .day, data: overview).pose == .calm)
    overview.agenda = snapshot.widgets!.tasks
    precondition(PomodoistWidgetPomoState(kind: .day, data: overview).pose == .focus)
    precondition(PomodoistWidgetPomoState(kind: .progress, data: overview).pose == .happy)
    for pose in PomodoistWidgetPomoState.Pose.allCases {
      let url = URL(fileURLWithPath: "apple/FocusWidget/Pomo/\(pose.rawValue)-still.webp")
      let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
      precondition(image.width == 384 && image.height == 384)
    }
    print("Apple widget snapshot checks passed")
  }
}
