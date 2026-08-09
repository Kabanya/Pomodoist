import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  func testWidgetSnapshotExcludesAccountSessionAndRoundTrips() {
    let snapshot: [String: Any] = [
      "version": 1,
      "focus": ["active": false],
    ]
    let widgetSnapshot = focusSnapshotDictionary(from: [
      "snapshot": snapshot,
      "accountSession": ["accessToken": "secret"],
    ])

    XCTAssertEqual(widgetSnapshot["version"] as? Int, 1)
    XCTAssertNil(widgetSnapshot["accountSession"])

    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let store = PomodoistFocusSnapshotStore(defaults: defaults, fileURL: fileURL)
    store.save(dictionary: widgetSnapshot)

    XCTAssertEqual(store.load(), .empty)
  }
}
