// Isolated store capture entry point; production views and models are unchanged.
import SwiftUI

@main
struct PomodoistWatchApp: App {
  @StateObject private var store: WatchCompanionStore
  private let locale: String
  private let screen: String

  init() {
    let env = ProcessInfo.processInfo.environment
    locale = env["STORE_CAPTURE_LOCALE"] ?? "en"
    screen = env["STORE_CAPTURE_SCREEN"] ?? "focus"
    let words = (try? JSONDecoder().decode([String].self, from: Data((env["STORE_CAPTURE_TASKS"] ?? "[]").utf8))) ?? ["Review project", "Read a chapter"]
    let state = WatchCompanionStore(defaults: UserDefaults(suiteName: "store-capture")!, activateSession: false)
    let now = Date()
    let stamp = WatchDateCoding.string(from: now)
    let tasks = words.prefix(3).enumerated().map { index, text in
      WatchTask(id: "capture-\(index)", content: text, description: nil, projectId: "inbox", priority: index + 1, completed: false, schedule: nil, estimatedFocusIntervals: 2, completedFocusIntervals: 0, createdAt: stamp)
    }
    state.snapshot = WatchSnapshot(
      version: 1, generatedAt: stamp,
      focus: WatchFocusSnapshot(active: true, presetId: "capture", presetName: nil, preset: WatchFocusPreset(id: "capture", name: "Pomodoro", workSeconds: 1500, shortBreakSeconds: 300, longBreakSeconds: 900, intervalsBeforeLongBreak: 4, allowPause: true, strictMode: false),
        run: WatchFocusRun(id: "capture", status: "active", taskId: nil, projectId: nil, startedAt: stamp, completedWorkIntervals: 1, targetWorkIntervals: 4),
        interval: WatchFocusInterval(id: "capture", type: "work", status: "paused", plannedSeconds: 1500, startedAt: WatchDateCoding.string(from: now.addingTimeInterval(-300)), pausedAt: stamp, pausedTotalSeconds: 0, sequenceNumber: 2)),
      tasks: WatchTaskBuckets(today: tasks, inbox: tasks, recentAdded: tasks), projects: [], sync: .empty, locale: locale
    )
    _store = StateObject(wrappedValue: state)
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if screen == "tasks" {
          NavigationStack { WatchTaskListView(title: Text("browse.today"), tasks: store.snapshot.tasks.today) }
        } else if screen == "voice" {
          AddTaskTabView()
        } else {
          FocusTabView()
        }
      }
      .environmentObject(store)
      .environment(\.locale, Locale(identifier: locale))
    }
  }
}
