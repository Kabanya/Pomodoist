import Foundation

let pomodoistFocusAppGroupIdentifier = "group.com.pomodoist"
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
    defaults: UserDefaults? = UserDefaults(suiteName: pomodoistFocusAppGroupIdentifier),
    fileURL: URL? = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: pomodoistFocusAppGroupIdentifier)?
      .appendingPathComponent(pomodoistFocusSnapshotFileName)
  ) {
    self.defaults = defaults ?? .standard
    self.fileURL = fileURL
  }

  func save(dictionary: [String: Any]) {
    guard JSONSerialization.isValidJSONObject(dictionary),
      let data = try? JSONSerialization.data(withJSONObject: dictionary)
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

  static func stateLabel(focus: PomodoistFocusSnapshot) -> String {
    guard focus.isActive, let interval = focus.interval else {
      return "Ready to focus"
    }
    if interval.status == "paused" {
      return "Paused"
    }
    if interval.status == "ready" {
      return "Ready"
    }
    return intervalLabel(interval.type)
  }

  static func intervalLabel(_ type: String) -> String {
    switch type {
    case "work":
      return "Work"
    case "longBreak":
      return "Long break"
    default:
      return "Break"
    }
  }

  static func workProgressLabel(focus: PomodoistFocusSnapshot) -> String {
    let completed = max(0, focus.run?.completedWorkIntervals ?? 0)
    let target = max(1, focus.run?.targetWorkIntervals ?? 1)
    return "\(min(completed, target))/\(target)"
  }

  static func nextIntervalLabel(focus: PomodoistFocusSnapshot) -> String {
    guard focus.isActive, let interval = focus.interval else {
      return "Next: work"
    }
    return interval.type == "work" ? "Next: break" : "Next: work"
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
