import SwiftUI

struct WatchRootView: View {
  @EnvironmentObject private var store: WatchCompanionStore

  var body: some View {
    TabView(selection: $store.selectedTab) {
      FocusTabView()
        .tag(0)
      AddTaskTabView()
        .tag(1)
      BrowseTabView()
        .tag(2)
    }
  }
}

struct FocusTabView: View {
  @EnvironmentObject private var store: WatchCompanionStore

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { timeline in
      let focus = store.snapshot.focus
      let interval = focus.interval

      if focus.active, let interval {
        activeTimer(focus: focus, interval: interval, now: timeline.date)
      } else {
        startOnly
      }
    }
  }

  @ViewBuilder
  private var startOnly: some View {
    VStack {
      Spacer()
      Button {
        store.send(
          WatchCommand.focusStartDefault(
            presetId: store.snapshot.focus.presetId
          )
        )
      } label: {
        Text("focus.start")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(.red)
      Spacer()
    }
    .padding(.horizontal, 24)
  }

  private func activeTimer(focus: WatchFocusSnapshot, interval: WatchFocusInterval, now: Date) -> some View {
    let remaining = WatchTimerMath.remainingSeconds(now: now, interval: interval)
    let progress = WatchTimerMath.progress(now: now, interval: interval)
    let display = WatchFocusProgressDisplay.make(
      completed: focus.run?.completedWorkIntervals ?? 0,
      target: focus.run?.targetWorkIntervals ?? 1
    )

    return GeometryReader { geometry in
      let circleSize = max(0, min(geometry.size.width, geometry.size.height) - 10)
      let ringWidth: CGFloat = 15
      ZStack {
        ZStack {
          Circle()
            .inset(by: ringWidth / 2)
            .stroke(.secondary.opacity(0.25), lineWidth: ringWidth)
          Circle()
            .inset(by: ringWidth / 2)
            .trim(from: 0, to: max(0, min(1, progress)))
            .stroke(.red, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
          VStack(spacing: 9) {
            Text(formatTime(remaining))
              .font(.system(size: 38, weight: .semibold, design: .rounded))
              .monospacedDigit()
              .minimumScaleFactor(0.75)
              .lineLimit(1)
            focusProgress(display)
          }
          .frame(width: circleSize * 0.75)
        }
        .frame(width: circleSize, height: circleSize)
        .offset(y: -18)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .overlay(alignment: .topLeading) {
        iconButton("arrow.counterclockwise", "focus.restart", WatchCommand.focusRestartInterval())
          .padding(.top, -26)
          .padding(.leading, 6)
      }
      .overlay(alignment: .bottomLeading) {
        playbackButton(interval)
          .padding(.bottom, 6)
          .padding(.leading, 6)
      }
      .overlay(alignment: .bottomTrailing) {
        iconButton("checkmark", "focus.complete", WatchCommand.focusComplete())
          .padding(.bottom, 6)
          .padding(.trailing, 6)
      }
    }
  }

  @ViewBuilder
  private func playbackButton(_ interval: WatchFocusInterval) -> some View {
    if interval.status == "running" {
      iconButton("pause.fill", "focus.pause", WatchCommand.focusPause())
    } else if interval.status == "paused" {
      iconButton("play.fill", "focus.resume", WatchCommand.focusResume())
    } else {
      iconButton("play.fill", "focus.start", WatchCommand.focusRestartInterval())
    }
  }

  @ViewBuilder
  private func focusProgress(_ display: WatchFocusProgressDisplay) -> some View {
    switch display {
    case let .dots(completed, target):
      HStack(spacing: 5) {
        ForEach(0..<target, id: \.self) { index in
          Circle()
            .fill(index < completed ? Color.red : Color.clear)
            .overlay {
              Circle().stroke(.red.opacity(index < completed ? 0 : 0.8), lineWidth: 1.3)
            }
            .frame(width: 8, height: 8)
        }
      }
      .accessibilityElement()
      .accessibilityLabel(Text("focus.progress"))
      .accessibilityValue(Text("\(completed)/\(target)"))
    case let .fraction(completed, target):
      Text("\(completed)/\(target)")
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .accessibilityLabel(Text("focus.progress"))
    }
  }

  private func iconButton(_ systemName: String, _ titleKey: LocalizedStringKey, _ command: [String: Any]) -> some View {
    Button {
      store.send(command)
    } label: {
      Image(systemName: systemName)
        .font(.system(size: 16, weight: .semibold))
        .frame(width: 36, height: 36)
        .background(.black.opacity(0.65), in: Circle())
        .overlay {
          Circle().stroke(.secondary.opacity(0.35), lineWidth: 1)
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(titleKey))
  }

  private func formatTime(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }
}

struct AddTaskTabView: View {
  @EnvironmentObject private var store: WatchCompanionStore
  @State private var isProcessing = false
  @State private var transcript = ""
  @State private var drafts = [WatchTaskDraft]()
  @State private var localErrorKey: String?
  @State private var localErrorMessage: String?

  var body: some View {
    NavigationStack {
      List {
        transcriptInput

        ForEach($drafts) { $draft in
          VStack(alignment: .leading, spacing: 4) {
            TextField("add.draft", text: $draft.quickAdd)
            if let description = draft.description, !description.isEmpty {
              Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
              drafts.removeAll { $0.id == draft.id }
            } label: {
              Label("add.remove", systemImage: "trash")
            }
          }
        }

        if !drafts.isEmpty {
          Button {
            commitDrafts()
          } label: {
            Label("add.addDrafts", systemImage: "checkmark")
          }
        }

        Section("add.recent") {
          ForEach(store.snapshot.tasks.recentAdded) { task in
            WatchTaskRow(task: task)
          }
        }
      }
      .navigationTitle(Text("add.title"))
    }
  }

  private var transcriptInput: some View {
    VStack(spacing: 12) {
      TextField("add.dictatePlaceholder", text: $transcript)

      if isProcessing {
        ProgressView()
      }

      Button {
        analyzeTranscript()
      } label: {
        Label {
          Text("add.analyze")
            .frame(maxWidth: .infinity)
        } icon: {
          Image(systemName: "sparkles")
        }
      }
      .buttonStyle(.borderedProminent)
      .tint(.red)
      .disabled(isProcessing || transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

      if let message = localErrorMessage {
        Text(message)
          .font(.caption2)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      } else if let key = localErrorKey {
        Text(LocalizedStringKey(key))
          .font(.caption2)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      }
    }
    .listRowBackground(Color.clear)
  }

  private func analyzeTranscript() {
    localErrorKey = nil
    localErrorMessage = nil
    let value = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
      return
    }
    isProcessing = true
    store.send(
      WatchCommand.decomposeTranscript(value, locale: Locale.current.identifier),
      queueIfOffline: false
    ) { reply in
      isProcessing = false
      guard let values = reply["tasks"] as? [Any] else {
        drafts = []
        localErrorMessage = reply["error"] as? String
        localErrorKey = localErrorMessage == nil ? "add.textUnavailable" : nil
        return
      }
      drafts = values.compactMap(WatchTaskDraft.init(value:))
      localErrorMessage = nil
      localErrorKey = drafts.isEmpty ? "add.textUnavailable" : nil
    }
  }

  private func commitDrafts() {
    store.send(WatchCommand.commitDrafts(drafts)) { reply in
      if (reply["ok"] as? Bool) == true {
        drafts = []
      }
    }
  }
}

struct BrowseTabView: View {
  @EnvironmentObject private var store: WatchCompanionStore

  var body: some View {
    NavigationStack {
      List {
        Text(store.pendingCommands.isEmpty ? store.syncStatus : "Queued")
          .font(.caption2)
          .foregroundStyle(.secondary)

        NavigationLink {
          WatchTaskListView(title: Text("browse.today"), tasks: store.snapshot.tasks.today)
        } label: {
          BrowseRow(title: "browse.today", systemImage: "sun.max", count: store.snapshot.tasks.today.count)
        }
        NavigationLink {
          WatchTaskListView(title: Text("browse.upcoming"), tasks: store.snapshot.tasks.upcoming)
        } label: {
          BrowseRow(title: "browse.upcoming", systemImage: "calendar", count: store.snapshot.tasks.upcoming.count)
        }
        NavigationLink {
          WatchTaskListView(title: Text("browse.inbox"), tasks: store.snapshot.tasks.inbox)
        } label: {
          BrowseRow(title: "browse.inbox", systemImage: "tray", count: store.snapshot.tasks.inbox.count)
        }
        NavigationLink {
          ProjectListView(projects: store.snapshot.projects)
        } label: {
          BrowseRow(title: "browse.projects", systemImage: "folder", count: store.snapshot.projects.count)
        }
      }
      .navigationTitle(Text("browse.title"))
    }
  }
}

struct BrowseRow: View {
  var title: LocalizedStringKey
  var systemImage: String
  var count: Int

  var body: some View {
    Label {
      HStack {
        Text(title)
        Spacer()
        Text("\(count)")
          .foregroundStyle(.secondary)
      }
    } icon: {
      Image(systemName: systemImage)
        .foregroundStyle(.red)
    }
  }
}

struct WatchTaskListView: View {
  var title: Text
  var tasks: [WatchTask]

  var body: some View {
    List {
      if tasks.isEmpty {
        Text("browse.empty")
          .foregroundStyle(.secondary)
      } else {
        ForEach(tasks) { task in
          WatchTaskRow(task: task)
        }
      }
    }
    .navigationTitle(title)
  }
}

struct ProjectListView: View {
  @EnvironmentObject private var store: WatchCompanionStore
  var projects: [WatchProject]

  var body: some View {
    List(projects) { project in
      NavigationLink {
        WatchTaskListView(
          title: Text(project.name),
          tasks: store.snapshot.tasks.byProject[project.id] ?? []
        )
      } label: {
        HStack {
          Image(systemName: "folder")
            .foregroundStyle(.red)
          Text(project.name)
            .lineLimit(1)
          Spacer()
          Text("\(project.openTaskCount)")
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle(Text("browse.projects"))
  }
}

struct WatchTaskRow: View {
  @EnvironmentObject private var store: WatchCompanionStore
  @State private var showingReplaceConfirmation = false
  var task: WatchTask

  var body: some View {
    HStack(spacing: 8) {
      Button {
        store.send(task.completed ? WatchCommand.uncompleteTask(task.id) : WatchCommand.completeTask(task.id))
      } label: {
        Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(task.completed ? .green : .red)
      }
      .buttonStyle(.plain)

      Button {
        handleTaskTap()
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text(task.content)
            .lineLimit(2)
            .strikethrough(task.completed)
          HStack(spacing: 6) {
            if let label = scheduleLabel(task.schedule) {
              Text(label)
            }
            if let estimate = task.estimatedFocusIntervals {
              Text("\(task.completedFocusIntervals)/\(estimate)")
            }
          }
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
      }
      .buttonStyle(.plain)
      .disabled(task.completed)
      .accessibilityHint(Text("focus.startTask"))
    }
    .confirmationDialog(
      Text("focus.replaceTitle"),
      isPresented: $showingReplaceConfirmation,
      titleVisibility: .visible
    ) {
      Button("focus.replaceAction", role: .destructive) {
        startFocus(replaceActive: true)
      }
      Button("common.cancel", role: .cancel) {}
    }
  }

  private func handleTaskTap() {
    switch WatchTaskFocusAction.resolve(
      focus: store.snapshot.focus,
      taskId: task.id
    ) {
    case .start:
      startFocus(replaceActive: false)
    case .showCurrent:
      store.selectedTab = 0
    case .confirmReplacement:
      showingReplaceConfirmation = true
    }
  }

  private func startFocus(replaceActive: Bool) {
    store.send(
      WatchCommand.focusStartDefault(
        presetId: store.snapshot.focus.presetId,
        taskId: task.id,
        projectId: task.projectId,
        targetWorkIntervals: task.estimatedFocusIntervals ?? 1,
        replaceActive: replaceActive
      )
    )
    store.selectedTab = 0
  }

  private func scheduleLabel(_ schedule: WatchTaskSchedule?) -> String? {
    guard let schedule else {
      return nil
    }
    if let date = schedule.date {
      return date
    }
    if let start = schedule.start, let date = WatchTimerMath.parseDate(start) {
      return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }
    return nil
  }
}
