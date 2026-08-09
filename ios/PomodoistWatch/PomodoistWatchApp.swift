import SwiftUI

@main
struct PomodoistWatchApp: App {
  @StateObject private var store = WatchCompanionStore()

  var body: some Scene {
    WindowGroup {
      WatchRootView()
        .environmentObject(store)
    }
  }
}
