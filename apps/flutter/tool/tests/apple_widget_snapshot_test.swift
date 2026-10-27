import Foundation

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
    print("Apple widget snapshot checks passed")
  }
}
