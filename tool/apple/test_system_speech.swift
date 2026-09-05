// Run: swiftc apple/SystemSpeechTranscriber.swift tool/apple/test_system_speech.swift -o /tmp/test_system_speech && /tmp/test_system_speech
import AVFoundation
import Foundation
import Speech

private final class Recognizer {
  struct Request {
    let url: URL
    let onDevice: Bool
    let completion: (Result<SystemSpeechTranscript, Error>) -> Void
  }
  var requests: [Request] = []
  var cancellations = 0

  func recognize(
    _ url: URL, _ locale: String?, _ onDevice: Bool,
    _ completion: @escaping (Result<SystemSpeechTranscript, Error>) -> Void
  ) -> () -> Void {
    assert(locale == "ru-RU")
    requests.append(Request(url: url, onDevice: onDevice, completion: completion))
    return { self.cancellations += 1 }
  }
}

@main
struct SystemSpeechTests {
  static func wait(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !condition() && Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.001))
    }
    assert(condition(), "Timed out")
  }

  static func fixture(_ url: URL, seconds: Int) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * 16000))!
    buffer.frameLength = buffer.frameCapacity
    for index in 0..<Int(buffer.frameLength) {
      buffer.floatChannelData![0][index] = Float(index % 2048) / 2048
    }
    try autoreleasepool {
      let file = try AVAudioFile(forWriting: url, settings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
      ])
      try file.write(from: buffer)
      if #available(macOS 15.0, *) { file.close() }
    }
  }

  static func main() throws {
    var snapshots = SystemSpeechSnapshots()
    snapshots.update(text: "buy flower", start: 0, end: 1, committed: false)
    snapshots.update(text: "buy flowers", start: 0, end: 1, committed: true)
    snapshots.update(text: "buy flowers", start: 0, end: 1, committed: true)
    snapshots.update(text: "call", start: 3, end: 3.5, committed: false)
    snapshots.update(text: "call mom", start: 3, end: 4, committed: true)
    assert(snapshots.text == "buy flowers call mom")
    snapshots.update(text: "buy flowers call mom", start: 0, end: 4, committed: true)
    assert(snapshots.text == "buy flowers call mom")
    snapshots.update(text: "call mom", start: 6, end: 7, committed: true)
    assert(snapshots.text == "buy flowers call mom call mom")
    snapshots.update(text: "", start: 0, end: 0, committed: true)
    assert(snapshots.text == "buy flowers call mom call mom")
    var segmented = SystemSpeechSnapshots()
    segmented.update(parts: [(.init(text: "buy flowers", start: 0, end: 1)),
      (.init(text: "call mom", start: 3, end: 4))], committed: true)
    segmented.update(text: "call mom", start: 3, end: 4, committed: true)
    assert(segmented.text == "buy flowers call mom", "Tail-only final must preserve cumulative prefix")
    var pendingTail = SystemSpeechSnapshots()
    pendingTail.update(parts: [.init(text: "buy flowers", start: 0, end: 1),
      .init(text: "call mom", start: 3, end: 4)], committed: false)
    pendingTail.update(text: "call mom", start: 3, end: 4, committed: true)
    assert(pendingTail.text == "buy flowers call mom", "Tail final must preserve pending prefix")
    var shorter = SystemSpeechSnapshots()
    shorter.update(parts: [.init(text: "buy", start: 0, end: 1),
      .init(text: "flowers", start: 1, end: 2)], committed: true)
    shorter.update(text: "buy", start: 0, end: 1, committed: true)
    assert(shorter.text == "buy", "Shorter revision must remove trailing words")
    var metadataRevision = SystemSpeechSnapshots()
    metadataRevision.update(parts: [.init(text: "buy", start: 0.2, end: 1),
      .init(text: "flowers", start: 1, end: 2)], committed: true, utteranceStart: 0)
    metadataRevision.update(parts: [.init(text: "buy", start: 0.3, end: 0.8)],
      committed: true, utteranceStart: 0)
    assert(metadataRevision.text == "buy")
    metadataRevision.update(parts: [.init(text: "buy", start: 0.3, end: 0.8),
      .init(text: "call mom", start: 3.2, end: 4)], committed: true, utteranceStart: 3)
    metadataRevision.update(parts: [.init(text: "call mom", start: 3.1, end: 3.9)],
      committed: true, utteranceStart: 3)
    assert(metadataRevision.text == "buy call mom")
    var pendingMetadata = SystemSpeechSnapshots()
    pendingMetadata.update(parts: [.init(text: "buy", start: 0.2, end: 1),
      .init(text: "flowers", start: 1, end: 2)], committed: false)
    pendingMetadata.update(parts: [.init(text: "buy", start: 0.3, end: 0.8)],
      committed: true, utteranceStart: 0)
    assert(pendingMetadata.text == "buy", "Metadata identity must replace the provisional utterance including its old tail")
    var shortenedTail = SystemSpeechSnapshots()
    shortenedTail.update(parts: [.init(text: "buy flowers", start: 0, end: 1),
      .init(text: "call", start: 3, end: 3.4),
      .init(text: "mom", start: 3.5, end: 4)], committed: false)
    shortenedTail.update(parts: [.init(text: "call", start: 3, end: 3.4)],
      committed: true, utteranceStart: 3)
    assert(shortenedTail.text == "buy flowers call", "Metadata tail revision must remove obsolete trailing words from a cumulative snapshot")
    shortenedTail.update(parts: [.init(text: "call mom", start: 6, end: 7)],
      committed: true, utteranceStart: 6)
    shortenedTail.update(parts: [.init(text: "call", start: 3, end: 3.4)],
      committed: true, utteranceStart: 3)
    assert(shortenedTail.text == "buy flowers call call mom", "A tail revision must preserve separately identified later utterances")
    var metadataFreeTail = SystemSpeechSnapshots()
    metadataFreeTail.update(parts: [.init(text: "buy flowers", start: 0, end: 1),
      .init(text: "call", start: 3, end: 3.4),
      .init(text: "mom", start: 3.5, end: 4)], committed: false)
    metadataFreeTail.update(parts: [.init(text: "call", start: 3, end: 3.4)], committed: true)
    assert(metadataFreeTail.text == "buy flowers call", "A metadata-free shortened tail must remove its obsolete suffix")
    var noSpaces = SystemSpeechSnapshots()
    noSpaces.update(parts: [.init(text: "今日", start: 0, end: 1),
      .init(text: "の予定", start: 1, end: 2, separator: "")], committed: true)
    noSpaces.update(text: "の予定", start: 1, end: 2, committed: true)
    assert(noSpaces.text == "今日の予定")
    let disabled = NSError(domain: "kLSRErrorDomain", code: 201)
    let wrapped = NSError(domain: "kAFAssistantErrorDomain", code: 1101,
      userInfo: [NSUnderlyingErrorKey: disabled])
    assert(SystemSpeechError.classify(wrapped).code == "speech_dictation_disabled")
    assert(SystemSpeechError.classify(NSError(domain: "kAFAssistantErrorDomain", code: 1101)).code == "speech_recognition_failed")
    assert(SystemSpeechError.classify(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)).code == "speech_network_unavailable")
    assert(SystemSpeechAccess.recognizer("zz-ZZ") == nil)
    assert(SystemSpeechAccess.recognizer("invalidlanguage") == nil)
    let supported = SFSpeechRecognizer.supportedLocales()
    for language in ["en", "ru", "de", "fr", "es", "ar", "zh"] {
      if supported.contains(where: { $0.languageCode == language }) {
        let resolved = SystemSpeechAccess.recognizer(language)
        assert(resolved?.locale.languageCode == language, "Regionless UI language must resolve within that language: \(language)")
      }
    }
    for locale in supported {
      assert(SystemSpeechAccess.recognizer(locale.identifier)?.locale.identifier == locale.identifier)
    }
    let choices: Set<Locale> = [Locale(identifier: "en-US"), Locale(identifier: "en-GB"),
      Locale(identifier: "zh-CN"), Locale(identifier: "zh-TW")]
    assert(SystemSpeechAccess.resolveLocale("en", supported: choices, region: "GB")?.identifier == "en-GB")
    assert(SystemSpeechAccess.resolveLocale("en", supported: choices, region: "RU")?.identifier == "en-US")
    assert(SystemSpeechAccess.resolveLocale("en-US", supported: choices, region: "GB")?.identifier == "en-US")
    assert(SystemSpeechAccess.resolveLocale("zh-Hant", supported: choices, region: "CN")?.identifier == "zh-TW")
    assert(SystemSpeechAccess.resolveLocale("zh-Hans", supported: choices, region: "TW")?.identifier == "zh-CN")
    assert(SystemSpeechAccess.resolveLocale("en-Cyrl", supported: choices, region: "US") == nil)
    assert(SystemSpeechAccess.resolveLocale("en-NZ", supported: choices, region: "US") == nil)
    let support = try FileManager.default.url(for: .applicationSupportDirectory,
      in: .userDomainMask, appropriateFor: nil, create: true)
    let storage = support.appendingPathComponent("pomodoist-native-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: storage) }
    try SystemSpeechAccess.prepareStorage(storage.path)
    let backupValues = try storage.resourceValues(forKeys: [.isExcludedFromBackupKey])
    assert(backupValues.isExcludedFromBackup == true)

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for seconds in [59, 60, 90, 300] {
      for onDevice in [false, true] {
        let audio = directory.appendingPathComponent("coverage-\(seconds)-\(onDevice).wav")
        try fixture(audio, seconds: seconds)
        let fake = Recognizer()
        let worker = SystemSpeechTranscriber(recognize: fake.recognize)
        var done: Result<SystemSpeechTranscript, Error>?
        worker.transcribe(url: audio, locale: "ru-RU", onDevice: onDevice) { done = $0 }
        let count = (seconds + 58) / 59
        var covered = 0
        for index in 0..<count {
          wait { fake.requests.count == index + 1 }
          let request = fake.requests[index]
          let file = try AVAudioFile(forReading: request.url)
          assert(file.length <= 59 * 16000, "Every mode must chunk at 59 seconds")
          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
          try file.read(into: buffer)
          for frame in 0..<Int(buffer.frameLength) {
            assert(buffer.floatChannelData![0][frame] == Float((covered + frame) % 2048) / 2048)
          }
          covered += Int(buffer.frameLength)
          request.completion(.success(SystemSpeechTranscript(text: "part\(index)", confidence: nil)))
          request.completion(.success(SystemSpeechTranscript(text: "duplicate", confidence: nil)))
        }
        wait { done != nil }
        assert(covered == seconds * 16000)
        let text = try done!.get().text
        assert(text == (0..<count).map { "part\($0)" }.joined(separator: " "))
      }
    }
    let emptyChunkAudio = directory.appendingPathComponent("empty-chunk.wav")
    try fixture(emptyChunkAudio, seconds: 90)
    let emptyFake = Recognizer()
    let emptyWorker = SystemSpeechTranscriber(recognize: emptyFake.recognize)
    var emptyOutcome: Result<SystemSpeechTranscript, Error>?
    emptyWorker.transcribe(url: emptyChunkAudio, locale: "ru-RU", onDevice: true) { emptyOutcome = $0 }
    emptyFake.requests[0].completion(.success(SystemSpeechTranscript(text: " ", confidence: nil)))
    wait { emptyOutcome != nil || emptyFake.requests.count > 1 }
    assert(emptyOutcome != nil, "An empty chunk must fail the whole transcription")
    if case .success = emptyOutcome! { assertionFailure("Empty chunk must fail") }
    assert(SystemSpeechAccess.speechStatus(.restricted) == "restricted")
    assert(SystemSpeechAccess.speechStatus(.notDetermined) == "notDetermined")
    do {
      try SystemSpeechAccess.prepareStorage(directory.path)
      assertionFailure("Outside Application Support must be rejected")
    } catch { assert((error as? SystemSpeechError)?.code == "invalid_recording_storage") }
    let source = directory.appendingPathComponent("five-minutes.wav")
    try fixture(source, seconds: 300)
    let recognizer = Recognizer()
    let transcriber = SystemSpeechTranscriber(recognize: recognizer.recognize)
    var outcomes: [Result<SystemSpeechTranscript, Error>] = []
    transcriber.transcribe(url: source, locale: "ru-RU", onDevice: false) { outcomes.append($0) }
    var offset = 0
    for index in 0..<6 {
      wait { recognizer.requests.count == index + 1 }
      let request = recognizer.requests[index]
      assert(!request.onDevice)
      let file = try AVAudioFile(forReading: request.url)
      assert(file.length > 0 && file.length <= 944000)
      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
      while file.framePosition < file.length {
        try file.read(into: buffer)
        assert(buffer.frameLength > 0)
        for frame in 0..<Int(buffer.frameLength) {
          assert(buffer.floatChannelData![0][frame] == Float((offset + frame) % 2048) / 2048)
        }
        offset += Int(buffer.frameLength)
      }
      assert(outcomes.isEmpty, "Must not report a partial transcript as complete")
      request.completion(.success(SystemSpeechTranscript(text: "part\(index)", confidence: 0.5)))
    }
    wait { outcomes.count == 1 }
    let combined = try outcomes[0].get()
    assert(combined.text == "part0 part1 part2 part3 part4 part5")
    assert(offset == 4800000)
    assert(recognizer.requests.allSatisfy { !FileManager.default.fileExists(atPath: $0.url.path) })
    assert(FileManager.default.fileExists(atPath: source.path))

    let short = directory.appendingPathComponent("short.wav")
    try fixture(short, seconds: 1)
    // Cancellation invalidates callbacks before a new request starts.
    transcriber.transcribe(url: source, locale: "ru-RU", onDevice: true) { outcomes.append($0) }
    wait { recognizer.requests.count == 7 }
    let canceled = recognizer.requests[6]
    assert(canceled.url != source && canceled.onDevice)
    transcriber.cancel()
    assert(recognizer.cancellations == 1 && outcomes.count == 2)
    if case .success = outcomes[1] { assertionFailure("Cancellation must fail") }
    transcriber.transcribe(url: short, locale: "ru-RU", onDevice: true) { outcomes.append($0) }
    wait { recognizer.requests.count == 8 }
    canceled.completion(.success(SystemSpeechTranscript(text: "stale", confidence: nil)))
    recognizer.requests[7].completion(.success(SystemSpeechTranscript(text: "current", confidence: nil)))
    wait { outcomes.count == 3 }
    let current = try outcomes[2].get()
    assert(current.text == "current")
    assert(FileManager.default.fileExists(atPath: source.path))

    // A failed later fragment must discard earlier text and remove all fragments.
    let first = recognizer.requests.count
    transcriber.transcribe(url: source, locale: "ru-RU", onDevice: false) { outcomes.append($0) }
    wait { recognizer.requests.count == first + 1 }
    let chunkDirectory = recognizer.requests[first].url.deletingLastPathComponent()
    recognizer.requests[first].completion(.success(SystemSpeechTranscript(text: "partial", confidence: nil)))
    wait { recognizer.requests.count == first + 2 }
    recognizer.requests[first + 1].completion(.failure(NSError(domain: "test", code: 1)))
    wait { outcomes.count == 4 }
    if case .success = outcomes[3] { assertionFailure("Fragment error must fail the entire request") }
    assert(!FileManager.default.fileExists(atPath: chunkDirectory.path))

    transcriber.transcribe(url: short, locale: "ru-RU", onDevice: false) { outcomes.append($0) }
    let shortRequest = recognizer.requests.last!
    assert(shortRequest.url == short)
    shortRequest.completion(.success(SystemSpeechTranscript(text: "  ", confidence: nil)))
    wait { outcomes.count == 5 }
    if case .success = outcomes[4] { assertionFailure("Empty transcript must fail") }
    assert(FileManager.default.fileExists(atPath: short.path))
    // Cancellation also removes the server-mode fragments.
    transcriber.transcribe(url: source, locale: "ru-RU", onDevice: false) { outcomes.append($0) }
    let active = recognizer.requests.last!
    let canceledDirectory = active.url.deletingLastPathComponent()
    var rejected = false
    transcriber.transcribe(url: short, locale: "ru-RU", onDevice: true) { result in
      if case .failure(let error) = result {
        rejected = (error as? SystemSpeechError)?.code == "speech_already_active"
      }
    }
    assert(rejected)
    transcriber.cancel()
    assert(outcomes.count == 6)
    assert(!FileManager.default.fileExists(atPath: canceledDirectory.path))
    assert(FileManager.default.fileExists(atPath: source.path))
    print("System speech: audio coverage, sequence, on-device, cancellation, stale callbacks, errors and cleanup passed")
  }
}
