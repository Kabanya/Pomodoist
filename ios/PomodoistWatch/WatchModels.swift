import Foundation

enum WatchDateCoding {
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

struct WatchSnapshot: Codable, Equatable {
  var version: Int
  var generatedAt: String?
  var focus: WatchFocusSnapshot
  var tasks: WatchTaskBuckets
  var projects: [WatchProject]
  var sync: WatchSyncSnapshot

  static let empty = WatchSnapshot(
    version: 1,
    generatedAt: nil,
    focus: WatchFocusSnapshot.empty,
    tasks: WatchTaskBuckets.empty,
    projects: [],
    sync: WatchSyncSnapshot.empty
  )

  init(
    version: Int,
    generatedAt: String?,
    focus: WatchFocusSnapshot,
    tasks: WatchTaskBuckets,
    projects: [WatchProject],
    sync: WatchSyncSnapshot
  ) {
    self.version = version
    self.generatedAt = generatedAt
    self.focus = focus
    self.tasks = tasks
    self.projects = projects
    self.sync = sync
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(Int.self, forKey: .version)
    generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
    focus = try container.decode(WatchFocusSnapshot.self, forKey: .focus)
    tasks = try container.decode(WatchTaskBuckets.self, forKey: .tasks)
    projects = try container.decode([WatchProject].self, forKey: .projects)
    sync = try container.decodeIfPresent(WatchSyncSnapshot.self, forKey: .sync) ?? .empty
  }

  static func decode(from value: Any?) -> WatchSnapshot? {
    let dictionary: [String: Any]?
    if let wrapped = value as? [String: Any], let snapshot = wrapped["snapshot"] as? [String: Any] {
      dictionary = snapshot
    } else {
      dictionary = value as? [String: Any]
    }
    guard let dictionary else {
      return nil
    }
    guard JSONSerialization.isValidJSONObject(dictionary),
      let data = try? JSONSerialization.data(withJSONObject: dictionary)
    else {
      return nil
    }
    return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
  }
}

struct WatchSyncSnapshot: Codable, Equatable {
  var appliedCommandIds: [String]

  static let empty = WatchSyncSnapshot(appliedCommandIds: [])
}

struct WatchFocusSnapshot: Codable, Equatable {
  var active: Bool
  var presetId: String?
  var presetName: String?
  var preset: WatchFocusPreset?
  var run: WatchFocusRun?
  var interval: WatchFocusInterval?

  static let empty = WatchFocusSnapshot(
    active: false,
    presetId: nil,
    presetName: nil,
    preset: nil,
    run: nil,
    interval: nil
  )
}

struct WatchFocusPreset: Codable, Equatable {
  var id: String
  var name: String
  var workSeconds: Int
  var shortBreakSeconds: Int
  var longBreakSeconds: Int
  var intervalsBeforeLongBreak: Int
  var allowPause: Bool
  var strictMode: Bool
}

struct WatchFocusRun: Codable, Equatable {
  var id: String
  var status: String
  var taskId: String?
  var projectId: String?
  var startedAt: String
  var completedWorkIntervals: Int
  var targetWorkIntervals: Int
}

struct WatchFocusInterval: Codable, Equatable {
  var id: String
  var type: String
  var status: String
  var plannedSeconds: Int
  var startedAt: String
  var pausedAt: String?
  var pausedTotalSeconds: Int
  var sequenceNumber: Int
}

struct WatchTaskBuckets: Codable, Equatable {
  var today: [WatchTask]
  var upcoming: [WatchTask]
  var inbox: [WatchTask]
  var recentAdded: [WatchTask]
  var byProject: [String: [WatchTask]]

  static let empty = WatchTaskBuckets()

  init(
    today: [WatchTask] = [],
    upcoming: [WatchTask] = [],
    inbox: [WatchTask] = [],
    recentAdded: [WatchTask] = [],
    byProject: [String: [WatchTask]] = [:]
  ) {
    self.today = today
    self.upcoming = upcoming
    self.inbox = inbox
    self.recentAdded = recentAdded
    self.byProject = byProject
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    today = try container.decode([WatchTask].self, forKey: .today)
    upcoming = try container.decode([WatchTask].self, forKey: .upcoming)
    inbox = try container.decode([WatchTask].self, forKey: .inbox)
    recentAdded = try container.decode([WatchTask].self, forKey: .recentAdded)
    byProject = try container.decodeIfPresent(
      [String: [WatchTask]].self,
      forKey: .byProject
    ) ?? [:]
  }
}

struct WatchTask: Codable, Equatable, Identifiable {
  var id: String
  var content: String
  var description: String?
  var projectId: String
  var priority: Int
  var completed: Bool
  var schedule: WatchTaskSchedule?
  var estimatedFocusIntervals: Int?
  var completedFocusIntervals: Int
  var createdAt: String?
}

struct WatchTaskSchedule: Codable, Equatable {
  var kind: String
  var date: String?
  var start: String?
  var end: String?
  var durationSeconds: Int?
}

struct WatchProject: Codable, Equatable, Identifiable {
  var id: String
  var name: String
  var color: String?
  var openTaskCount: Int
}

struct WatchPendingCommand: Codable, Equatable, Identifiable {
  var id: String
  var type: String
  var createdAt: String
  var occurredAt: String
  var baseSnapshotGeneratedAt: String?
  private var payloadData: Data

  init?(command: [String: Any]) {
    guard let id = command["id"] as? String,
      let type = command["type"] as? String,
      let createdAt = command["createdAt"] as? String,
      let occurredAt = command["occurredAt"] as? String,
      JSONSerialization.isValidJSONObject(command),
      let data = try? JSONSerialization.data(withJSONObject: command)
    else {
      return nil
    }
    self.id = id
    self.type = type
    self.createdAt = createdAt
    self.occurredAt = occurredAt
    self.baseSnapshotGeneratedAt = command["baseSnapshotGeneratedAt"] as? String
    payloadData = data
  }

  var payload: [String: Any] {
    guard let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
      return [:]
    }
    return object
  }
}

struct WatchTaskDraft: Identifiable, Equatable {
  var id = UUID()
  var quickAdd: String
  var description: String?

  init(id: UUID = UUID(), quickAdd: String, description: String?) {
    self.id = id
    self.quickAdd = quickAdd
    self.description = description
  }

  init?(value: Any) {
    guard let dictionary = value as? [String: Any],
      let quickAdd = dictionary["quickAdd"] as? String,
      !quickAdd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return nil
    }
    self.quickAdd = quickAdd
    self.description = dictionary["description"] as? String
  }

  var payload: [String: Any] {
    var payload: [String: Any] = ["quickAdd": quickAdd]
    if let description, !description.isEmpty {
      payload["description"] = description
    }
    return payload
  }
}

enum WatchFocusProgressDisplay: Equatable {
  case dots(completed: Int, target: Int)
  case fraction(completed: Int, target: Int)

  static func make(completed: Int, target: Int) -> WatchFocusProgressDisplay {
    let safeTarget = max(1, target)
    let safeCompleted = max(0, min(completed, safeTarget))
    if safeTarget <= 8 {
      return .dots(completed: safeCompleted, target: safeTarget)
    }
    return .fraction(completed: safeCompleted, target: safeTarget)
  }
}

enum WatchTaskFocusAction: Equatable {
  case start
  case showCurrent
  case confirmReplacement

  static func resolve(
    focus: WatchFocusSnapshot,
    taskId: String
  ) -> WatchTaskFocusAction {
    guard focus.active else {
      return .start
    }
    return focus.run?.taskId == taskId ? .showCurrent : .confirmReplacement
  }
}

enum WatchCommand {
  static func createQuickAdd(
    _ input: String,
    baseSnapshotGeneratedAt: String? = nil,
    now: Date = Date()
  ) -> [String: Any] {
    withMetadata(
      ["type": "task.createQuickAdd", "input": input],
      baseSnapshotGeneratedAt: baseSnapshotGeneratedAt,
      now: now
    )
  }

  static func decomposeTranscript(
    _ transcript: String,
    locale: String,
    baseSnapshotGeneratedAt: String? = nil,
    now: Date = Date()
  ) -> [String: Any] {
    withMetadata(
      ["type": "task.decomposeTranscript", "transcript": transcript, "locale": locale],
      baseSnapshotGeneratedAt: baseSnapshotGeneratedAt,
      now: now
    )
  }

  static func commitDrafts(
    _ drafts: [WatchTaskDraft],
    baseSnapshotGeneratedAt: String? = nil,
    now: Date = Date()
  ) -> [String: Any] {
    withMetadata(
      ["type": "task.commitDrafts", "tasks": drafts.map(\.payload)],
      baseSnapshotGeneratedAt: baseSnapshotGeneratedAt,
      now: now
    )
  }

  static func completeTask(
    _ id: String,
    baseSnapshotGeneratedAt: String? = nil,
    now: Date = Date()
  ) -> [String: Any] {
    withMetadata(
      ["type": "task.complete", "taskId": id],
      baseSnapshotGeneratedAt: baseSnapshotGeneratedAt,
      now: now
    )
  }

  static func uncompleteTask(
    _ id: String,
    baseSnapshotGeneratedAt: String? = nil,
    now: Date = Date()
  ) -> [String: Any] {
    withMetadata(
      ["type": "task.uncomplete", "taskId": id],
      baseSnapshotGeneratedAt: baseSnapshotGeneratedAt,
      now: now
    )
  }

  static func focusStartDefault(
    presetId: String? = nil,
    taskId: String? = nil,
    projectId: String? = nil,
    targetWorkIntervals: Int? = nil,
    replaceActive: Bool = false,
    baseSnapshotGeneratedAt: String? = nil,
    now: Date = Date()
  ) -> [String: Any] {
    var command: [String: Any] = ["type": "focus.startDefault"]
    if let presetId {
      command["presetId"] = presetId
    }
    if let taskId {
      command["taskId"] = taskId
    }
    if let projectId {
      command["projectId"] = projectId
    }
    if let targetWorkIntervals {
      command["targetWorkIntervals"] = max(1, targetWorkIntervals)
    }
    if replaceActive {
      command["replaceActive"] = true
    }
    return withMetadata(
      command,
      baseSnapshotGeneratedAt: baseSnapshotGeneratedAt,
      now: now
    )
  }

  static func focusPause(
    baseSnapshotGeneratedAt: String? = nil,
    now: Date = Date()
  ) -> [String: Any] {
    withMetadata(["type": "focus.pause"], baseSnapshotGeneratedAt: baseSnapshotGeneratedAt, now: now)
  }

  static func focusResume(
    baseSnapshotGeneratedAt: String? = nil,
    now: Date = Date()
  ) -> [String: Any] {
    withMetadata(["type": "focus.resume"], baseSnapshotGeneratedAt: baseSnapshotGeneratedAt, now: now)
  }

  static func focusRestartInterval(
    baseSnapshotGeneratedAt: String? = nil,
    now: Date = Date()
  ) -> [String: Any] {
    withMetadata(["type": "focus.restartInterval"], baseSnapshotGeneratedAt: baseSnapshotGeneratedAt, now: now)
  }

  static func focusComplete(
    baseSnapshotGeneratedAt: String? = nil,
    now: Date = Date()
  ) -> [String: Any] {
    withMetadata(["type": "focus.complete"], baseSnapshotGeneratedAt: baseSnapshotGeneratedAt, now: now)
  }

  static func focusSkip(
    baseSnapshotGeneratedAt: String? = nil,
    now: Date = Date()
  ) -> [String: Any] {
    withMetadata(["type": "focus.skip"], baseSnapshotGeneratedAt: baseSnapshotGeneratedAt, now: now)
  }

  static func focusStop(
    baseSnapshotGeneratedAt: String? = nil,
    now: Date = Date()
  ) -> [String: Any] {
    withMetadata(["type": "focus.stop"], baseSnapshotGeneratedAt: baseSnapshotGeneratedAt, now: now)
  }

  static func snapshotRequest(now: Date = Date()) -> [String: Any] {
    withMetadata(["type": "snapshot.request"], now: now)
  }

  static func withMetadata(
    _ command: [String: Any],
    baseSnapshotGeneratedAt: String? = nil,
    now: Date = Date()
  ) -> [String: Any] {
    var result = command
    let timestamp = WatchDateCoding.string(from: now)
    result["id"] = (result["id"] as? String) ?? UUID().uuidString
    result["createdAt"] = (result["createdAt"] as? String) ?? timestamp
    result["occurredAt"] = (result["occurredAt"] as? String) ?? timestamp
    if result["baseSnapshotGeneratedAt"] == nil, let baseSnapshotGeneratedAt {
      result["baseSnapshotGeneratedAt"] = baseSnapshotGeneratedAt
    }
    return result
  }
}

enum WatchTimerMath {
  static func remainingSeconds(now: Date, interval: WatchFocusInterval) -> Int {
    if interval.status == "ready" {
      return interval.plannedSeconds
    }
    let startedAt = parseDate(interval.startedAt) ?? now
    let effectiveNow = interval.pausedAt.flatMap(parseDate) ?? now
    let elapsed = Int(effectiveNow.timeIntervalSince(startedAt)) - interval.pausedTotalSeconds
    return max(0, min(interval.plannedSeconds, interval.plannedSeconds - elapsed))
  }

  static func progress(now: Date, interval: WatchFocusInterval) -> Double {
    guard interval.plannedSeconds > 0 else {
      return 0
    }
    let remaining = remainingSeconds(now: now, interval: interval)
    return 1 - (Double(remaining) / Double(interval.plannedSeconds))
  }

  static func parseDate(_ value: String) -> Date? {
    WatchDateCoding.date(from: value)
  }
}
