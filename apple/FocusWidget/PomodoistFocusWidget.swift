import SwiftUI
import WidgetKit
#if os(iOS)
import UIKit
#endif

struct PomodoistFocusEntry: TimelineEntry {
  let date: Date
  let snapshot: PomodoistSnapshot
}

struct PomodoistFocusProvider: TimelineProvider {
  func placeholder(in context: Context) -> PomodoistFocusEntry {
    PomodoistFocusEntry(date: Date(), snapshot: .sample)
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (PomodoistFocusEntry) -> Void
  ) {
    completion(PomodoistFocusEntry(date: Date(), snapshot: loadSnapshot()))
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<PomodoistFocusEntry>) -> Void
  ) {
    let now = Date()
    let snapshot = loadSnapshot()
    let dates = PomodoistFocusDisplay.timelineDates(now: now, focus: snapshot.focus)
    let entries = dates.map { PomodoistFocusEntry(date: $0, snapshot: snapshot) }
    let reload = snapshot.focus.interval?.status == "running"
      ? (dates.last ?? now).addingTimeInterval(60)
      : now.addingTimeInterval(15 * 60)
    completion(
      Timeline(
        entries: entries,
        policy: .after(reload)
      )
    )
  }

  private func loadSnapshot() -> PomodoistSnapshot {
    PomodoistFocusSnapshotStore().load()
  }

}

struct PomodoistFocusWidgetView: View {
  @Environment(\.widgetFamily) private var family

  let entry: PomodoistFocusEntry

  @ViewBuilder
  var body: some View {
    if #available(iOS 17.0, macOS 14.0, *) {
      content.containerBackground(for: .widget) {
        widgetBackground
      }
    } else {
      content.background(widgetBackground)
    }
  }

  private var widgetBackground: Color {
    #if os(iOS)
    Color(UIColor.systemBackground)
    #else
    Color.clear
    #endif
  }

  private var content: some View {
    Group {
      switch family {
      case .systemSmall:
        small
      case .systemMedium:
        medium
      default:
        large
      }
    }
    .widgetURL(URL(string: "pomodoist://focus"))
  }

  private var focus: PomodoistFocusSnapshot {
    entry.snapshot.focus
  }

  private var accent: Color {
    if let rawValue = UserDefaults(suiteName: pomodoistFocusAppGroupIdentifier)?
      .string(forKey: pomodoistTimerColorDefaultsKey),
      let color = PomodoistTimerColor(rawValue: rawValue)
    {
      switch color {
      case .white: return .white
      case .black: return .black
      case .red: return .red
      case .green: return .green
      case .blue: return .blue
      case .orange: return .orange
      case .purple: return .purple
      }
    }
    guard focus.isActive, let interval = focus.interval else {
      return .red
    }
    if interval.status == "paused" {
      return Color.secondary
    }
    return interval.type == "work" ? .red : Color(red: 0, green: 0.5, blue: 0.5)
  }

  private var presetName: String {
    focus.presetName ?? focus.preset?.name ?? "Pomodoist"
  }

  private var stateLabel: String {
    PomodoistFocusDisplay.stateLabel(focus: focus)
  }

  private var small: some View {
    VStack(spacing: 8) {
      ring(size: 78, lineWidth: 8, fontSize: 22)
      Text(stateLabel)
        .font(.caption2.weight(.semibold))
        .foregroundColor(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .padding(12)
  }

  private var medium: some View {
    HStack(spacing: 16) {
      ring(size: 96, lineWidth: 10, fontSize: 26)

      VStack(alignment: .leading, spacing: 6) {
        Text(presetName)
          .font(.headline)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
        Text(stateLabel)
          .font(.subheadline)
          .foregroundColor(.secondary)
          .lineLimit(1)
        Text(PomodoistFocusDisplay.workProgressLabel(focus: focus))
          .font(.caption.monospacedDigit().weight(.semibold))
          .padding(.top, 4)
      }
      Spacer(minLength: 0)
    }
    .padding(16)
  }

  private var large: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(presetName)
            .font(.headline)
            .lineLimit(1)
          Text(stateLabel)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
        Spacer()
        Text(PomodoistFocusDisplay.workProgressLabel(focus: focus))
          .font(.callout.monospacedDigit().weight(.semibold))
          .foregroundColor(accent)
      }

      HStack(spacing: 20) {
        ring(size: 128, lineWidth: 12, fontSize: 34)
        VStack(alignment: .leading, spacing: 12) {
          progressDots
          Text(PomodoistFocusDisplay.nextIntervalLabel(focus: focus))
            .font(.subheadline)
            .foregroundColor(.secondary)
            .lineLimit(1)
          if let preset = focus.preset {
            Text("\(preset.workSeconds / 60)m work")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        Spacer(minLength: 0)
      }
    }
    .padding(18)
  }

  private var progressDots: some View {
    let completed = max(0, min(focus.run?.completedWorkIntervals ?? 0, focus.run?.targetWorkIntervals ?? 1))
    let target = max(1, focus.run?.targetWorkIntervals ?? 1)
    return Group {
      if target <= 8 {
        HStack(spacing: 6) {
          ForEach(0..<target, id: \.self) { index in
            Circle()
              .fill(index < completed ? accent : Color.clear)
              .overlay(
                Circle().stroke(accent.opacity(index < completed ? 0 : 0.75), lineWidth: 1.2)
              )
              .frame(width: 9, height: 9)
          }
        }
      } else {
        Text("\(completed)/\(target)")
          .font(.caption.monospacedDigit())
          .foregroundColor(.secondary)
      }
    }
  }

  private func ring(size: CGFloat, lineWidth: CGFloat, fontSize: CGFloat) -> some View {
    let progress = PomodoistFocusDisplay.progress(now: entry.date, focus: focus)
    return ZStack {
      Circle()
        .stroke(Color.secondary.opacity(0.18), lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: max(0, min(1, progress)))
        .stroke(
          accent,
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
      timerText(fontSize: fontSize)
        .frame(width: size * 0.72)
    }
    .frame(width: size, height: size)
  }

  @ViewBuilder
  private func timerText(fontSize: CGFloat) -> some View {
    if let interval = focus.interval,
      let end = PomodoistFocusDisplay.intervalEndDate(now: entry.date, interval: interval),
      end > entry.date
    {
      if #available(iOS 16.0, macOS 13.0, *) {
        styledTimer(
          Text(
            timerInterval: entry.date...end,
            countsDown: true,
            showsHours: false
          ),
          fontSize: fontSize
        )
      } else {
        staticTimer(fontSize: fontSize)
      }
    } else {
      staticTimer(fontSize: fontSize)
    }
  }

  private func staticTimer(fontSize: CGFloat) -> some View {
    styledTimer(
      Text(
        PomodoistFocusDisplay.format(
          seconds: PomodoistFocusDisplay.displaySeconds(now: entry.date, focus: focus)
        )
      ),
      fontSize: fontSize
    )
  }

  private func styledTimer(_ text: Text, fontSize: CGFloat) -> some View {
    text
      .font(.system(size: fontSize, weight: .semibold, design: .rounded).monospacedDigit())
      .lineLimit(1)
      .minimumScaleFactor(0.55)
  }
}

@main
struct PomodoistFocusWidget: Widget {
  let kind = pomodoistFocusWidgetKind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: PomodoistFocusProvider()) { entry in
      PomodoistFocusWidgetView(entry: entry)
    }
    .configurationDisplayName("Pomodoist Focus")
    .description("Shows the current Pomodoist timer.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

private extension PomodoistSnapshot {
  static let sample = PomodoistSnapshot(
    version: 1,
    generatedAt: PomodoistDateCoding.string(from: Date()),
    focus: PomodoistFocusSnapshot(
      active: true,
      presetId: "classic",
      presetName: "Classic",
      preset: PomodoistFocusPreset(
        id: "classic",
        name: "Classic",
        workSeconds: 25 * 60,
        shortBreakSeconds: 5 * 60,
        longBreakSeconds: 15 * 60,
        intervalsBeforeLongBreak: 4,
        allowPause: true,
        strictMode: false
      ),
      run: PomodoistFocusRun(
        id: "sample-run",
        status: "active",
        taskId: nil,
        projectId: nil,
        startedAt: PomodoistDateCoding.string(from: Date().addingTimeInterval(-20 * 60)),
        completedWorkIntervals: 1,
        targetWorkIntervals: 4
      ),
      interval: PomodoistFocusInterval(
        id: "sample-interval",
        type: "work",
        status: "running",
        plannedSeconds: 25 * 60,
        startedAt: PomodoistDateCoding.string(from: Date().addingTimeInterval(-20 * 60)),
        pausedAt: nil,
        pausedTotalSeconds: 0,
        sequenceNumber: 1
      )
    )
  )
}
