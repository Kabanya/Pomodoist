// Run: swiftc apple/SystemSpeechTranscriber.swift tool/apple/test_system_speech.swift -o /tmp/test_system_speech && /tmp/test_system_speech
import AVFoundation
import Foundation

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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
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

    // On-device processing keeps the original five-minute file intact.
    transcriber.transcribe(url: source, locale: "ru-RU", onDevice: true) { outcomes.append($0) }
    wait { recognizer.requests.count == 7 }
    let canceled = recognizer.requests[6]
    assert(canceled.url == source && canceled.onDevice)
    transcriber.cancel()
    assert(recognizer.cancellations == 1 && outcomes.count == 2)
    if case .success = outcomes[1] { assertionFailure("Cancellation must fail") }
    transcriber.transcribe(url: source, locale: "ru-RU", onDevice: true) { outcomes.append($0) }
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

    let short = directory.appendingPathComponent("short.wav")
    try fixture(short, seconds: 1)
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
