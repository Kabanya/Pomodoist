import Foundation

@main
struct FocusLocalizationTests {
  static func main() throws {
    let old = try JSONEncoder().encode(PomodoistSnapshot.empty)
    var snapshot = try JSONDecoder().decode(PomodoistSnapshot.self, from: old)
    assert(snapshot.locale == nil)
    for locale in ["pt-BR", "ja", "ko"] {
      snapshot.locale = locale
      let decoded = try JSONDecoder().decode(PomodoistSnapshot.self, from: JSONEncoder().encode(snapshot))
      assert(decoded.locale == locale)
      assert(decoded.focus == snapshot.focus)
    }
    // Compile and run from an app bundle with apple/Localization in Resources.
    if Bundle.main.path(forResource: "ja", ofType: "lproj") != nil {
      assert(pomodoistLocalized("Pause", locale: "ja-JP") == "一時停止")
      assert(pomodoistLocalized("Pause", locale: "ko-KR") == "일시 정지")
      assert(pomodoistLocalized("Pause", locale: "pt") == "Pausar")
      assert(pomodoistLocalized("Pause", locale: "pt-PT") == "Pausar")
      assert(pomodoistLocalized("Pause", locale: "xx") == "Pause")
    } else {
      fatalError("Localization resource bundle is required")
    }
    print("Focus snapshots: backward compatibility, locale propagation and native fallback passed")
  }
}
