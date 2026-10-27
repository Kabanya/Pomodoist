import Foundation
#if os(iOS)
import ActivityKit
import AppIntents
#endif

func pomodoistLocalized(_ key: String, locale: String? = nil) -> String {
  let requested = locale.map { [$0] } ?? Locale.preferredLanguages
  for tag in requested {
    let base = tag.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").first.map(String.init) ?? "en"
    let resource = base == "pt" ? "pt-BR" : base
    if let path = Bundle.main.path(forResource: resource, ofType: "lproj"), let bundle = Bundle(path: path) {
      return bundle.localizedString(forKey: key, value: key, table: nil)
    }
  }
  return key
}

let pomodoistFocusAppGroupIdentifier =
  Bundle.main.object(forInfoDictionaryKey: "PomodoistAppGroup") as? String ?? ""
let pomodoistFocusURLScheme =
  Bundle.main.object(forInfoDictionaryKey: "PomodoistURLScheme") as? String ?? "pomodoist"
let pomodoistFocusSnapshotDefaultsKey = "focus.snapshot.v1"
let pomodoistFocusSnapshotFileName = "focus-snapshot-v1.json"
let pomodoistTimerColorDefaultsKey = "focus.statusItem.timerColor"
let pomodoistFocusWidgetKind = "PomodoistFocusWidget"
let watchCompanionChannelName = "pomodoist/watch_companion"

enum PomodoistTimerColor: String, CaseIterable {
  case white
  case black
  case red
  case green
  case blue
  case orange
  case purple
}

enum PomodoistDateCoding {
  static func string(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  static func date(from value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) {
      return date
    }
    return ISO8601DateFormatter().date(from: value)
  }
}

struct PomodoistSnapshot: Codable, Equatable {
  var version: Int
  var generatedAt: String?
  var focus: PomodoistFocusSnapshot
  var locale: String? = nil
  var widgets: PomodoistWidgetSnapshot? = nil

  static let empty = PomodoistSnapshot(
    version: 1,
    generatedAt: nil,
    focus: .empty
  )

  static func decode(from value: Any?) -> PomodoistSnapshot? {
    let dictionary: [String: Any]?
    if let wrapped = value as? [String: Any],
      let snapshot = wrapped["snapshot"] as? [String: Any]
    {
      dictionary = snapshot
    } else {
      dictionary = value as? [String: Any]
    }
    guard let dictionary,
      JSONSerialization.isValidJSONObject(dictionary),
      let data = try? JSONSerialization.data(withJSONObject: dictionary)
    else {
      return nil
    }
    return try? JSONDecoder().decode(PomodoistSnapshot.self, from: data)
  }
}

struct PomodoistWidgetSnapshot: Codable, Equatable {
  var day: String
  var focusTaskTitle: String?
  var tasks: [PomodoistWidgetTask]
  var agenda: [PomodoistWidgetTask]
  var habits: [PomodoistWidgetHabit]
  var totalHabits: Int
  var completedHabits: Int
  var completedTasks: Int
  var week: [PomodoistWidgetDay]

  func isCurrent(on date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return day == String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  var focusSeconds: Int { week.reduce(0) { $0 + max(0, $1.focusSeconds) } }
}

struct PomodoistWidgetTask: Codable, Equatable, Identifiable {
  var id: String
  var title: String
  var start: String?
}

struct PomodoistWidgetHabit: Codable, Equatable, Identifiable {
  var id: String
  var title: String
  var count: Int
  var target: Int
  var completed: Bool
}

struct PomodoistWidgetDay: Codable, Equatable, Identifiable {
  var day: String
  var focusSeconds: Int
  var id: String { day }

  var date: Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: day)
  }
}

func pomodoistWidgetURL(screen: String, taskID: String? = nil) -> URL? {
  var components = URLComponents()
  components.scheme = pomodoistFocusURLScheme
  components.host = "widget"
  components.queryItems = [URLQueryItem(name: "screen", value: screen)]
  if let taskID { components.queryItems?.append(URLQueryItem(name: "task", value: taskID)) }
  return components.url
}

#if os(iOS)
@available(iOS 16.2, *)
struct PomodoistFocusActivityAttributes: ActivityAttributes {
  var runID: String

  struct ContentState: Codable, Hashable {
    var title: String
    var label: String
    var intervalID: String
    var end: Date?
    var seconds: Int
    var completed: Int
    var target: Int
    var progress: Double
    var canPause: Bool
    var paused: Bool

    init?(snapshot: PomodoistSnapshot, now: Date) {
      let focus = snapshot.focus
      guard focus.isActive, let interval = focus.interval, let run = focus.run else { return nil }
      title = snapshot.widgets?.focusTaskTitle ?? focus.presetName ?? "Pomodoist"
      label = PomodoistFocusDisplay.stateLabel(focus: focus, locale: snapshot.locale)
      intervalID = interval.id
      end = PomodoistFocusDisplay.intervalEndDate(now: now, interval: interval)
      seconds = PomodoistFocusDisplay.remainingSeconds(now: now, interval: interval)
      completed = max(0, run.completedWorkIntervals)
      target = max(1, run.targetWorkIntervals)
      progress = PomodoistFocusDisplay.progress(now: now, focus: focus)
      canPause = focus.preset?.allowPause == true && focus.preset?.strictMode != true
        && ["running", "paused"].contains(interval.status)
      paused = interval.status == "paused"
    }
  }
}

@MainActor
enum PomodoistWidgetCommands {
  static var handler: (([String: Any], @escaping ([String: Any]) -> Void) -> Void)?

  static func send(type: String, taskID: String? = nil, intervalID: String? = nil) async throws {
    // The foreground intent can arrive while Flutter's engine is starting.
    for _ in 0..<20 where handler == nil {
      try await Task.sleep(nanoseconds: 250_000_000)
    }
    guard let handler else { throw commandError() }
    var command = PomodoistFocusCommand.make(type: type)
    command["taskId"] = taskID
    command["expectedIntervalId"] = intervalID
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      handler(command) { reply in
        if reply["ok"] as? Bool == true {
          continuation.resume()
        } else {
          continuation.resume(throwing: commandError())
        }
      }
    }
  }

  private static func commandError() -> NSError {
    NSError(domain: "PomodoistWidget", code: 1,
      userInfo: [NSLocalizedDescriptionKey: pomodoistLocalized("Open Pomodoist to update")])
  }
}

@available(iOS 17.0, *)
struct PomodoistFocusPlaybackIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Pause or resume focus"
  static var openAppWhenRun = true
  @Parameter(title: "Interval") var intervalID: String
  @Parameter(title: "Resume") var resume: Bool

  init() {}
  init(intervalID: String, resume: Bool) { self.intervalID = intervalID; self.resume = resume }

  func perform() async throws -> some IntentResult {
    try await PomodoistWidgetCommands.send(
      type: resume ? PomodoistFocusCommand.resume : PomodoistFocusCommand.pause,
      intervalID: intervalID)
    return .result()
  }
}

@available(iOS 17.0, *)
struct PomodoistCompleteTaskIntent: AppIntent {
  static var title: LocalizedStringResource = "Complete task"
  static var openAppWhenRun = true
  @Parameter(title: "Task") var taskID: String

  init() {}
  init(taskID: String) { self.taskID = taskID }
  func perform() async throws -> some IntentResult {
    try await PomodoistWidgetCommands.send(type: "task.complete", taskID: taskID)
    return .result()
  }
}
#endif

struct PomodoistFocusSnapshot: Codable, Equatable {
  var active: Bool
  var presetId: String?
  var presetName: String?
  var preset: PomodoistFocusPreset?
  var run: PomodoistFocusRun?
  var interval: PomodoistFocusInterval?

  static let empty = PomodoistFocusSnapshot(
    active: false,
    presetId: nil,
    presetName: nil,
    preset: nil,
    run: nil,
    interval: nil
  )

  var isActive: Bool {
    active && run != nil && interval != nil
  }
}

struct PomodoistFocusPreset: Codable, Equatable {
  var id: String
  var name: String
  var workSeconds: Int
  var shortBreakSeconds: Int
  var longBreakSeconds: Int
  var intervalsBeforeLongBreak: Int
  var allowPause: Bool
  var strictMode: Bool
}

struct PomodoistFocusRun: Codable, Equatable {
  var id: String
  var status: String
  var taskId: String?
  var projectId: String?
  var startedAt: String
  var completedWorkIntervals: Int
  var targetWorkIntervals: Int
}

struct PomodoistFocusInterval: Codable, Equatable {
  var id: String
  var type: String
  var status: String
  var plannedSeconds: Int
  var startedAt: String
  var pausedAt: String?
  var pausedTotalSeconds: Int
  var sequenceNumber: Int
}

struct PomodoistFocusSnapshotStore {
  var defaults: UserDefaults
  var fileURL: URL?

  init(
    defaults: UserDefaults? = pomodoistFocusAppGroupIdentifier.isEmpty
      ? nil : UserDefaults(suiteName: pomodoistFocusAppGroupIdentifier),
    fileURL: URL? = pomodoistFocusAppGroupIdentifier.isEmpty ? nil : FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: pomodoistFocusAppGroupIdentifier)?
      .appendingPathComponent(pomodoistFocusSnapshotFileName)
  ) {
    self.defaults = defaults ?? .standard
    self.fileURL = fileURL
  }

  func save(dictionary: [String: Any]) {
    guard let snapshot = PomodoistSnapshot.decode(from: dictionary),
      let data = try? JSONEncoder().encode(snapshot)
    else {
      return
    }
    if let fileURL {
      try? data.write(to: fileURL, options: .atomic)
    }
    defaults.set(data, forKey: pomodoistFocusSnapshotDefaultsKey)
  }

  func load() -> PomodoistSnapshot {
    let fileData = fileURL.flatMap { try? Data(contentsOf: $0) }
    for data in [fileData, defaults.data(forKey: pomodoistFocusSnapshotDefaultsKey)] {
      guard let data,
        let object = try? JSONSerialization.jsonObject(with: data),
        let snapshot = PomodoistSnapshot.decode(from: object)
      else {
        continue
      }
      return snapshot
    }
    return .empty
  }
}

enum PomodoistFocusCommand {
  static let startDefault = "focus.startDefault"
  static let pause = "focus.pause"
  static let resume = "focus.resume"
  static let restartInterval = "focus.restartInterval"
  static let complete = "focus.complete"
  static let stop = "focus.stop"
  static let snapshotRequest = "snapshot.request"

  static func make(
    type: String,
    baseSnapshotGeneratedAt: String? = nil,
    now: Date = Date()
  ) -> [String: Any] {
    let timestamp = PomodoistDateCoding.string(from: now)
    var command: [String: Any] = [
      "type": type,
      "id": UUID().uuidString,
      "createdAt": timestamp,
      "occurredAt": timestamp,
    ]
    if let baseSnapshotGeneratedAt {
      command["baseSnapshotGeneratedAt"] = baseSnapshotGeneratedAt
    }
    return command
  }
}

enum PomodoistFocusDisplay {
  static func title(now: Date, focus: PomodoistFocusSnapshot) -> String {
    "\u{25EF} \(timerText(now: now, focus: focus))"
  }

  static func timerText(now: Date, focus: PomodoistFocusSnapshot) -> String {
    format(seconds: displaySeconds(now: now, focus: focus))
  }

  static func displaySeconds(now: Date, focus: PomodoistFocusSnapshot) -> Int {
    guard focus.isActive, let interval = focus.interval else {
      return max(0, focus.preset?.workSeconds ?? 25 * 60)
    }
    return remainingSeconds(now: now, interval: interval)
  }

  static func remainingSeconds(now: Date, interval: PomodoistFocusInterval) -> Int {
    if interval.status == "ready" {
      return interval.plannedSeconds
    }
    let startedAt = PomodoistDateCoding.date(from: interval.startedAt) ?? now
    let effectiveNow = interval.pausedAt.flatMap(PomodoistDateCoding.date) ?? now
    let elapsed = Int(effectiveNow.timeIntervalSince(startedAt)) - interval.pausedTotalSeconds
    return max(0, min(interval.plannedSeconds, interval.plannedSeconds - elapsed))
  }

  static func progress(now: Date, focus: PomodoistFocusSnapshot) -> Double {
    guard focus.isActive, let interval = focus.interval, interval.plannedSeconds > 0 else {
      return 0
    }
    let remaining = remainingSeconds(now: now, interval: interval)
    return 1 - (Double(remaining) / Double(interval.plannedSeconds))
  }

  static func intervalEndDate(now: Date, interval: PomodoistFocusInterval) -> Date? {
    guard interval.status == "running" else {
      return nil
    }
    let remaining = remainingSeconds(now: now, interval: interval)
    return now.addingTimeInterval(TimeInterval(remaining))
  }

  static func format(seconds: Int) -> String {
    let safeSeconds = max(0, seconds)
    return String(format: "%02d:%02d", safeSeconds / 60, safeSeconds % 60)
  }

  static func stateLabel(focus: PomodoistFocusSnapshot, locale: String? = nil) -> String {
    guard focus.isActive, let interval = focus.interval else {
      return pomodoistLocalized("Ready to focus", locale: locale)
    }
    if interval.status == "paused" {
      return pomodoistLocalized("Paused", locale: locale)
    }
    if interval.status == "ready" {
      return pomodoistLocalized("Ready", locale: locale)
    }
    return intervalLabel(interval.type, locale: locale)
  }

  static func intervalLabel(_ type: String, locale: String? = nil) -> String {
    switch type {
    case "work":
      return pomodoistLocalized("Work", locale: locale)
    case "longBreak":
      return pomodoistLocalized("Long break", locale: locale)
    default:
      return pomodoistLocalized("Break", locale: locale)
    }
  }

  static func workProgressLabel(focus: PomodoistFocusSnapshot) -> String {
    let completed = max(0, focus.run?.completedWorkIntervals ?? 0)
    let target = max(1, focus.run?.targetWorkIntervals ?? 1)
    return "\(min(completed, target))/\(target)"
  }

  static func nextIntervalLabel(focus: PomodoistFocusSnapshot, locale: String? = nil) -> String {
    guard focus.isActive, let interval = focus.interval else {
      return pomodoistLocalized("Next: work", locale: locale)
    }
    return pomodoistLocalized(interval.type == "work" ? "Next: break" : "Next: work", locale: locale)
  }

  static func primaryStartCommand(focus: PomodoistFocusSnapshot) -> String? {
    guard focus.isActive else {
      return PomodoistFocusCommand.startDefault
    }
    return focus.interval?.status == "ready"
      ? PomodoistFocusCommand.restartInterval
      : nil
  }

  static func timelineDates(
    now: Date,
    focus: PomodoistFocusSnapshot,
    cadence: TimeInterval = 60
  ) -> [Date] {
    guard focus.isActive,
      let interval = focus.interval,
      let end = intervalEndDate(now: now, interval: interval),
      end > now
    else {
      return [now]
    }

    let step = max(1, cadence)
    var dates = [now]
    var next = now.addingTimeInterval(step)
    while next < end {
      dates.append(next)
      next = next.addingTimeInterval(step)
    }
    dates.append(end)
    return dates
  }
}
