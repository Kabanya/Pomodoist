import SwiftUI
import WidgetKit
import ImageIO
#if os(iOS)
import UIKit
import ActivityKit
#elseif os(macOS)
import AppKit
#endif

struct PomodoistFocusEntry: TimelineEntry {
  let date: Date
  let snapshot: PomodoistSnapshot
}

struct PomodoistFocusProvider: TimelineProvider {
  func placeholder(in context: Context) -> PomodoistFocusEntry {
    PomodoistFocusEntry(date: Date(), snapshot: .sample)
  }

  func getSnapshot(in context: Context, completion: @escaping (PomodoistFocusEntry) -> Void) {
    completion(PomodoistFocusEntry(date: Date(), snapshot: context.isPreview ? .sample : PomodoistFocusSnapshotStore().load()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<PomodoistFocusEntry>) -> Void) {
    let now = Date()
    let snapshot = PomodoistFocusSnapshotStore().load()
    var dates = PomodoistFocusDisplay.timelineDates(now: now, focus: snapshot.focus)
    let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now)!)
    dates.append(midnight)
    completion(Timeline(entries: Array(Set(dates)).sorted().map {
      PomodoistFocusEntry(date: $0, snapshot: snapshot)
    }, policy: .after(min(now.addingTimeInterval(15 * 60), midnight))))
  }
}

private func widgetFamilies() -> [WidgetFamily] {
  #if os(watchOS)
  return [.accessoryRectangular, .accessoryCircular, .accessoryInline]
  #elseif os(iOS)
  if #available(iOS 16.0, *) {
    return [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline]
  }
  return [.systemSmall, .systemMedium, .systemLarge]
  #else
  return [.systemSmall, .systemMedium, .systemLarge]
  #endif
}

private var widgetBackground: Color {
  #if os(iOS)
  Color(UIColor.systemBackground)
  #elseif os(watchOS)
  Color.black
  #else
  Color(NSColor.windowBackgroundColor)
  #endif
}

private extension View {
  @ViewBuilder
  func quietAccentable() -> some View {
    if #available(iOS 16.0, macOS 13.0, watchOS 9.0, *) { widgetAccentable() } else { self }
  }
  @ViewBuilder
  func quietWidgetBackground(compact: Bool) -> some View {
    if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
      containerBackground(for: .widget) { widgetBackground }
    } else {
      padding(compact ? 0 : 16).background(widgetBackground)
    }
  }
}

private extension WidgetFamily {
  var quietIsSmall: Bool {
    #if os(watchOS)
    false
    #else
    self == .systemSmall
    #endif
  }
  var quietIsLarge: Bool {
    #if os(watchOS)
    false
    #else
    self == .systemLarge
    #endif
  }
  var quietIsInline: Bool {
    #if os(macOS)
    false
    #else
    if #available(iOS 16.0, *) { return self == .accessoryInline }
    return false
    #endif
  }
  var quietIsCircular: Bool {
    #if os(macOS)
    false
    #else
    if #available(iOS 16.0, *) { return self == .accessoryCircular }
    return false
    #endif
  }
  var quietIsCompact: Bool {
    #if os(macOS)
    false
    #else
    if #available(iOS 16.0, *) { return self == .accessoryRectangular || quietIsCircular || quietIsInline }
    return false
    #endif
  }
}

private var quietAccent: Color { Color(red: 0.85, green: 0.23, blue: 0.18) }

private struct PomodoistWidgetPomo: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.self) private var environment
  let state: PomodoistWidgetPomoState
  var centered = false

  private var luminanceReduced: Bool {
    if #available(iOS 16.0, macOS 13.0, watchOS 8.0, *) {
      return environment.isLuminanceReduced
    }
    return false
  }

  private static let images: [PomodoistWidgetPomoState.Pose: CGImage] = Dictionary(
    uniqueKeysWithValues: PomodoistWidgetPomoState.Pose.allCases.compactMap { pose in
      guard let url = Bundle.main.url(forResource: "\(pose.rawValue)-still", withExtension: "webp", subdirectory: "Pomo"),
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
      return (pose, image)
    })

  var body: some View {
    GeometryReader { geometry in
      let side = max(0, min(128, geometry.size.width, geometry.size.height))
      let still = reduceMotion || luminanceReduced
      ZStack {
        if side >= 32, let image = Self.images[state.pose] {
          Image(decorative: image, scale: 1)
            .resizable().scaledToFit().frame(width: side, height: side)
            .id(state)
            .transition(still ? .identity : .scale(scale: 0.92, anchor: .bottom)
              .combined(with: .offset(y: 8)).combined(with: .opacity))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centered ? .bottom : .bottomTrailing)
      .animation(still ? nil : .easeInOut(duration: 2), value: state)
    }
    .frame(minHeight: 0)
    .layoutPriority(-1)
    .clipped()
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }
}

struct PomodoistFocusWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: PomodoistFocusEntry

  private var focus: PomodoistFocusSnapshot { entry.snapshot.focus }
  private var title: String {
    entry.snapshot.widgets?.focusTaskTitle ?? pomodoistLocalized(focus.presetName ?? "Pomodoist Focus", locale: entry.snapshot.locale)
  }
  private var state: String { PomodoistFocusDisplay.stateLabel(focus: focus, locale: entry.snapshot.locale) }
  private var timerColor: Color {
    if let raw = UserDefaults(suiteName: pomodoistFocusAppGroupIdentifier)?.string(forKey: pomodoistTimerColorDefaultsKey),
      let color = PomodoistTimerColor(rawValue: raw) {
      switch color {
      case .white: return .white
      case .black: return .black
      case .red: return quietAccent
      case .green: return .green
      case .blue: return .blue
      case .orange: return .orange
      case .purple: return .purple
      }
    }
    if focus.interval?.status == "paused" { return .secondary }
    if let interval = focus.interval, interval.type != "work" { return .teal }
    return quietAccent
  }

  @ViewBuilder
  private var timer: some View {
    if let interval = focus.interval,
      let end = PomodoistFocusDisplay.intervalEndDate(now: entry.date, interval: interval),
      end > entry.date
    {
      if #available(iOS 16.0, macOS 13.0, watchOS 9.0, *) {
        Text(timerInterval: entry.date...end, countsDown: true, showsHours: false)
      } else {
        Text(PomodoistFocusDisplay.timerText(now: entry.date, focus: focus))
      }
    } else {
      Text(PomodoistFocusDisplay.timerText(now: entry.date, focus: focus))
    }
  }

  var body: some View {
    content
      .quietWidgetBackground(compact: family.quietIsCompact)
      .widgetURL(URL(string: "\(pomodoistFocusURLScheme)://focus"))
  }

  @ViewBuilder
  private var content: some View {
    switch family {
    case .accessoryInline:
      HStack { timer; Text(state) }.lineLimit(1).minimumScaleFactor(0.6)
    case .accessoryCircular:
      VStack(spacing: 2) {
        timer.font(.system(size: 22, weight: .bold)).monospacedDigit().minimumScaleFactor(0.6)
        Text(PomodoistFocusDisplay.workProgressLabel(focus: focus)).font(.caption2)
      }
      .accessibilityElement(children: .combine)
    case .accessoryRectangular:
      HStack(spacing: 10) {
        timer.font(.system(size: 32, weight: .bold)).monospacedDigit().minimumScaleFactor(0.6)
        VStack(alignment: .leading, spacing: 3) {
          Text(title).font(.headline).lineLimit(1).privacySensitive()
          Text(state).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
      }
    default:
      VStack(alignment: .leading, spacing: 10) {
        if family.quietIsSmall {
          Text(state).font(.caption).foregroundStyle(.secondary)
          timerDisplay(size: 48)
          Text(title).font(.caption).lineLimit(2).privacySensitive()
          Spacer(minLength: 0)
        } else {
          HStack(alignment: .center, spacing: 16) {
            timerDisplay(size: family.quietIsLarge ? 76 : 54)
              .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
              Text(title).font(.headline).lineLimit(2).privacySensitive()
              Text(state).font(.caption).foregroundStyle(.secondary).lineLimit(1)
              Text(PomodoistFocusDisplay.workProgressLabel(focus: focus))
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          if family.quietIsLarge {
            PomodoistWidgetPomo(state: .init(focus: focus))
            Text(PomodoistFocusDisplay.nextIntervalLabel(focus: focus, locale: entry.snapshot.locale))
              .font(.subheadline).foregroundStyle(.secondary)
          }
        }
        ProgressView(value: PomodoistFocusDisplay.progress(now: entry.date, focus: focus))
          .tint(timerColor).accessibilityLabel(Text(state))
      }
    }
  }

  private func timerDisplay(size: CGFloat) -> some View {
    timer.font(.system(size: size, weight: .bold)).monospacedDigit()
      .foregroundStyle(timerColor).lineLimit(1).minimumScaleFactor(0.55)
      .quietAccentable()
  }
}

struct PomodoistFocusWidget: Widget {
  let kind = pomodoistFocusWidgetKind
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: PomodoistFocusProvider()) { entry in
      PomodoistFocusWidgetView(entry: entry)
    }
    .configurationDisplayName(pomodoistLocalized("Pomodoist Focus"))
    .description(pomodoistLocalized("Shows the current Pomodoist timer."))
    .supportedFamilies(widgetFamilies())
  }
}

extension PomodoistOverviewKind {
  var title: String {
    switch self {
    case .tasks: return "Tasks"
    case .habits: return "Habits"
    case .day: return "Day"
    case .progress: return "Progress"
    }
  }
  var detail: String {
    switch self {
    case .tasks: return "Shows your next tasks."
    case .habits: return "Shows today's habits."
    case .day: return "Shows today's schedule."
    case .progress: return "Shows this week's progress."
    }
  }
}

struct PomodoistOverviewWidget: Widget {
  let kind: PomodoistOverviewKind
  init() { kind = .tasks }
  init(kind: PomodoistOverviewKind) { self.kind = kind }
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "Pomodoist.\(kind.rawValue)", provider: PomodoistFocusProvider()) { entry in
      PomodoistOverviewView(kind: kind, entry: entry)
    }
    .configurationDisplayName("Pomodoist " + pomodoistLocalized(kind.title))
    .description(pomodoistLocalized(kind.detail))
    .supportedFamilies(widgetFamilies())
  }
}

struct PomodoistOverviewView: View {
  @Environment(\.widgetFamily) private var family
  let kind: PomodoistOverviewKind
  let entry: PomodoistFocusEntry

  private var compact: Bool {
    family.quietIsCompact
  }
  private var small: Bool { compact || family.quietIsSmall }
  private var data: PomodoistWidgetSnapshot? {
    guard let widgets = entry.snapshot.widgets, widgets.isCurrent(on: entry.date) else { return nil }
    return widgets
  }
  private func localized(_ text: String) -> String { pomodoistLocalized(text, locale: entry.snapshot.locale) }

  var body: some View {
    Group {
      if let data {
        if family.quietIsInline {
          inline(data)
        } else if family.quietIsCircular {
          circular(data)
        } else {
          full(data)
        }
      } else {
        VStack(alignment: .leading, spacing: 4) {
          Text(localized(kind.title)).font(.headline)
          Text(localized("Open Pomodoist to update")).font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .quietWidgetBackground(compact: family.quietIsCompact)
    .widgetURL(pomodoistWidgetURL(screen: kind.rawValue))
    .privacySensitive()
  }

  @ViewBuilder
  private func full(_ data: PomodoistWidgetSnapshot) -> some View {
    switch kind {
    case .tasks: tasks(data)
    case .habits: habits(data)
    case .day: agenda(data)
    case .progress: progress(data)
    }
  }

  @ViewBuilder
  private func inline(_ data: PomodoistWidgetSnapshot) -> some View {
    switch kind {
    case .tasks: Text(data.tasks.first?.title ?? localized("No tasks"))
    case .habits: Text("\(max(0, data.completedHabits)) / \(max(0, data.totalHabits)) " + localized("Habits"))
    case .day: Text(data.agenda.first?.title ?? localized("Nothing scheduled"))
    case .progress: Text(duration(data.focusSeconds))
    }
  }

  @ViewBuilder
  private func circular(_ data: PomodoistWidgetSnapshot) -> some View {
    switch kind {
    case .habits:
      ZStack {
        Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 3)
        Circle().trim(from: 0, to: min(1, Double(max(0, data.completedHabits)) / Double(max(1, data.totalHabits))))
          .stroke(quietAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
        Text("\(max(0, data.completedHabits))/\(max(0, data.totalHabits))").font(.caption).minimumScaleFactor(0.6)
      }.accessibilityLabel(localized("Habits"))
    case .progress:
      VStack(spacing: 1) {
        Text("\(max(0, data.completedTasks))").font(.system(size: 28, weight: .bold)).monospacedDigit()
        Text(localized("Tasks")).font(.caption2)
      }
    case .tasks:
      VStack(spacing: 2) {
        Image(systemName: "checklist")
        Text(localized(data.tasks.isEmpty ? "No tasks" : "Next"))
          .font(.caption2).lineLimit(1).minimumScaleFactor(0.6)
      }
    case .day:
      Text(entry.date, format: .dateTime.day()).font(.system(size: 28, weight: .bold))
    }
  }

  private func tasks(_ data: PomodoistWidgetSnapshot) -> some View {
    VStack(alignment: .leading, spacing: compact ? 3 : 10) {
      if let first = data.tasks.first {
          HStack(alignment: .top, spacing: 8) {
            taskAction(first)
            Link(destination: pomodoistWidgetURL(screen: "tasks", taskID: first.id)!) {
            Text(first.title).font(compact ? .headline : .system(size: small ? 21 : 25, weight: .bold))
              .lineLimit(small ? 2 : 3)
            }
          }
        if !small {
          Divider()
          Text(localized("Next")).font(.caption2).foregroundStyle(.secondary)
          ForEach(Array(data.tasks.dropFirst().prefix(family.quietIsLarge ? 5 : 2))) { task in
            Link(destination: pomodoistWidgetURL(screen: "tasks", taskID: task.id)!) {
              Text(task.title).font(.subheadline).lineLimit(1)
            }
          }
        }
      } else {
        Text(localized("No tasks")).font(.headline)
      }
      if family.quietIsLarge {
        PomodoistWidgetPomo(state: .init(kind: .tasks, data: data))
      } else if !compact { Spacer(minLength: 0) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func taskAction(_ task: PomodoistWidgetTask) -> some View {
    #if os(iOS)
    if #available(iOS 17.0, *), !compact {
      Button(intent: PomodoistCompleteTaskIntent(taskID: task.id)) {
        Image(systemName: "circle").font(.title3).frame(width: 44, height: 44)
      }.buttonStyle(.plain).foregroundStyle(quietAccent)
        .accessibilityLabel(pomodoistLocalized("Complete task") + ": " + task.title)
    } else {
      Image(systemName: "circle").foregroundStyle(quietAccent).accessibilityHidden(true)
    }
    #else
    Image(systemName: "circle").foregroundStyle(quietAccent).accessibilityHidden(true)
    #endif
  }

  private func habits(_ data: PomodoistWidgetSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text("\(max(0, data.completedHabits)) / \(max(0, data.totalHabits))")
            .font(.system(size: compact ? 25 : 34, weight: .bold)).monospacedDigit()
            .minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(quietAccent).quietAccentable()
          if !compact { Text(localized("Habits")).font(.caption).foregroundStyle(.secondary) }
        }
        if !family.quietIsSmall {
          VStack(alignment: .leading, spacing: compact ? 3 : 8) {
            ForEach(Array(data.habits.prefix(compact ? 2 : family.quietIsLarge ? 6 : 3))) { habit in
              HStack(spacing: 6) {
                Image(systemName: habit.completed ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(habit.completed ? quietAccent : Color.secondary)
                Text(habit.title).lineLimit(1)
                Spacer(minLength: 0)
                if !habit.completed { Text("\(max(0, habit.count))/\(max(1, habit.target))").monospacedDigit() }
              }.font(compact ? .caption : .subheadline)
            }
            if data.totalHabits == 0 { Text(localized("No habits today")).font(.caption) }
          }
        }
      }
      if family.quietIsLarge {
        PomodoistWidgetPomo(state: .init(kind: .habits, data: data), centered: true)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func agenda(_ data: PomodoistWidgetSnapshot) -> some View {
    VStack(alignment: .leading, spacing: compact ? 3 : 12) {
      if !compact {
        Text(entry.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
          .font(.headline).environment(\.locale, Locale(identifier: entry.snapshot.locale ?? "en"))
      }
      if data.agenda.isEmpty {
        Text(localized("Nothing scheduled")).font(.subheadline).foregroundStyle(.secondary)
      }
      ForEach(Array(data.agenda.prefix(compact ? 2 : small ? 2 : family.quietIsLarge ? 7 : 3))) { task in
        Link(destination: pomodoistWidgetURL(screen: "day", taskID: task.id)!) {
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
              if let start = task.start.flatMap(PomodoistDateCoding.date) {
                Text(start, style: .time)
              } else {
                Text(localized("All day"))
              }
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            .frame(width: compact ? 42 : 54, alignment: .leading)
            Rectangle().fill(quietAccent).frame(width: 2, height: compact ? 13 : 20)
            Text(task.title).font(compact ? .caption : .subheadline).lineLimit(1)
          }
        }
      }
      if family.quietIsLarge {
        PomodoistWidgetPomo(state: .init(kind: .day, data: data))
      } else if !compact { Spacer(minLength: 0) }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private func progress(_ data: PomodoistWidgetSnapshot) -> some View {
    VStack(alignment: .leading, spacing: compact ? 3 : 8) {
      Text(duration(data.focusSeconds))
        .font(.system(size: compact ? 26 : small ? 30 : 38, weight: .bold))
        .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
        .foregroundStyle(quietAccent).quietAccentable()
      if !compact {
        Text(localized("Focus this week")).font(.caption).foregroundStyle(.secondary)
        weekChart(data).frame(height: family.quietIsLarge ? 100 : 46)
      }
      Text(String(format: localized("%d tasks today"), max(0, data.completedTasks)))
        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
      if family.quietIsLarge {
        PomodoistWidgetPomo(state: .init(kind: .progress, data: data))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func weekChart(_ data: PomodoistWidgetSnapshot) -> some View {
    let maximum = max(1, data.week.map(\.focusSeconds).max() ?? 0)
    return GeometryReader { geometry in
      HStack(alignment: .bottom, spacing: 5) {
        ForEach(data.week) { day in
          VStack(spacing: 3) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2)
              .fill(day.focusSeconds > 0 ? quietAccent : Color.secondary.opacity(0.12))
              .frame(height: max(2, (geometry.size.height - 16) * CGFloat(max(0, day.focusSeconds)) / CGFloat(maximum)))
              .quietAccentable()
            if let date = day.date {
              Text(date, format: .dateTime.weekday(.narrow))
                .font(.caption2).foregroundStyle(.secondary)
                .environment(\.locale, Locale(identifier: entry.snapshot.locale ?? "en"))
            }
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel((day.date?.formatted(date: .abbreviated, time: .omitted) ?? day.day) + ": " + duration(day.focusSeconds))
        }
      }
    }
  }

  private func duration(_ seconds: Int) -> String {
    let formatter = DateComponentsFormatter()
    var calendar = Calendar.current
    calendar.locale = Locale(identifier: entry.snapshot.locale ?? "en")
    formatter.calendar = calendar
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: TimeInterval(max(0, seconds))) ?? "0"
  }
}

@main
struct PomodoistWidgetBundle: WidgetBundle {
  var body: some Widget {
    PomodoistFocusWidget()
    PomodoistOverviewWidget(kind: .tasks)
    PomodoistOverviewWidget(kind: .habits)
    PomodoistOverviewWidget(kind: .day)
    PomodoistOverviewWidget(kind: .progress)
    #if os(iOS)
    if #available(iOS 16.2, *) { PomodoistFocusActivityWidget() }
    #endif
  }
}

extension PomodoistSnapshot {
  static var sample: PomodoistSnapshot {
    let now = Date()
    let day = Calendar.current.startOfDay(for: now)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    let weekday = Calendar.current.component(.weekday, from: day)
    let monday = Calendar.current.date(byAdding: .day, value: -(weekday + 5) % 7, to: day)!
    var snapshot = PomodoistSnapshot(
      version: 1, generatedAt: PomodoistDateCoding.string(from: now),
      focus: PomodoistFocusSnapshot(
        active: true, presetId: "classic", presetName: "Classic",
        preset: PomodoistFocusPreset(id: "classic", name: "Classic", workSeconds: 1500,
          shortBreakSeconds: 300, longBreakSeconds: 900, intervalsBeforeLongBreak: 4,
          allowPause: true, strictMode: false),
        run: PomodoistFocusRun(id: "preview", status: "active", taskId: "design", projectId: nil,
          startedAt: PomodoistDateCoding.string(from: now), completedWorkIntervals: 1, targetWorkIntervals: 4),
        interval: PomodoistFocusInterval(id: "preview", type: "work", status: "running", plannedSeconds: 1500,
          startedAt: PomodoistDateCoding.string(from: now.addingTimeInterval(-378)),
          pausedAt: nil, pausedTotalSeconds: 0, sequenceNumber: 2)),
      locale: Locale.current.identifier)
    let tasks = [
      PomodoistWidgetTask(id: "design", title: "Design review", start: PomodoistDateCoding.string(from: day.addingTimeInterval(9.5 * 3600))),
      PomodoistWidgetTask(id: "proposal", title: "Send proposal", start: PomodoistDateCoding.string(from: day.addingTimeInterval(11 * 3600))),
      PomodoistWidgetTask(id: "launch", title: "Plan launch", start: PomodoistDateCoding.string(from: day.addingTimeInterval(14 * 3600))),
    ]
    snapshot.widgets = PomodoistWidgetSnapshot(day: formatter.string(from: day),
      focusTaskTitle: "Design review", tasks: tasks, agenda: tasks,
      habits: [
        PomodoistWidgetHabit(id: "read", title: "Read", count: 1, target: 1, completed: true),
        PomodoistWidgetHabit(id: "move", title: "Move", count: 1, target: 1, completed: true),
        PomodoistWidgetHabit(id: "water", title: "Water", count: 6, target: 8, completed: false),
      ], totalHabits: 3, completedHabits: 2, completedTasks: 8,
      week: (0..<7).map { offset in
        let date = Calendar.current.date(byAdding: .day, value: offset, to: monday)!
        return PomodoistWidgetDay(day: formatter.string(from: date), focusSeconds: date <= now ? (offset == 0 ? 7200 : offset == 1 ? 8400 : 0) : 0)
      })
    return snapshot
  }
}

#if os(iOS)
@available(iOS 16.2, *)
private struct ActivityTimer: View {
  let state: PomodoistFocusActivityAttributes.ContentState
  var body: some View {
    let now = Date()
    Group {
      if let end = state.end, end > now {
        Text(timerInterval: now...end, countsDown: true, showsHours: false)
      } else {
        Text(PomodoistFocusDisplay.format(seconds: state.end == nil ? state.seconds : 0))
      }
    }.monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
  }
}

@available(iOS 16.2, *)
struct PomodoistFocusActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: PomodoistFocusActivityAttributes.self) { context in
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 16) {
          ActivityTimer(state: context.state)
            .font(.system(size: 56, weight: .bold)).foregroundStyle(quietAccent)
            .frame(maxWidth: .infinity, alignment: .leading)
          VStack(alignment: .leading, spacing: 5) {
            Text(context.state.title).font(.headline).lineLimit(2).privacySensitive()
            Text(context.state.label).font(.caption).foregroundStyle(.secondary)
            Text("\(min(context.state.completed + 1, context.state.target)) / \(context.state.target)")
              .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
          }
          playback(context.state)
        }
        ProgressView(value: context.state.progress).tint(quietAccent)
      }
      .padding(16)
      .widgetURL(URL(string: "\(pomodoistFocusURLScheme)://focus"))
      .activityBackgroundTint(Color(UIColor.systemBackground))
      .activitySystemActionForegroundColor(.primary)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.state.title).font(.headline).lineLimit(1).privacySensitive()
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text("\(min(context.state.completed + 1, context.state.target)) / \(context.state.target)")
            .font(.caption.monospacedDigit())
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            ActivityTimer(state: context.state).font(.system(size: 40, weight: .bold))
              .frame(maxWidth: .infinity, alignment: .leading)
            playback(context.state)
          }
        }
      } compactLeading: {
        Image(systemName: "timer").foregroundStyle(quietAccent)
      } compactTrailing: {
        ActivityTimer(state: context.state).font(.caption).frame(width: 48)
      } minimal: {
        Image(systemName: "timer")
      }
      .widgetURL(URL(string: "\(pomodoistFocusURLScheme)://focus"))
      .keylineTint(quietAccent)
    }
  }

  @ViewBuilder
  private func playback(_ state: PomodoistFocusActivityAttributes.ContentState) -> some View {
    if state.canPause {
      if #available(iOS 17.0, *) {
        Button(intent: PomodoistFocusPlaybackIntent(intervalID: state.intervalID, resume: state.paused)) {
          Image(systemName: state.paused ? "play.fill" : "pause.fill")
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).foregroundStyle(quietAccent)
        .background(quietAccent.opacity(0.1), in: Circle())
        .accessibilityLabel(pomodoistLocalized(state.paused ? "Resume" : "Pause"))
      }
    }
  }
}
#endif
