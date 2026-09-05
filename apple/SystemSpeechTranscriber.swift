import AVFoundation
import Speech

struct SystemSpeechTranscript {
  let text: String
  let confidence: Double?
}

struct SystemSpeechError: LocalizedError {
  let code: String
  let message: String
  var domain: String = "pomodoist.system_speech"
  var nativeCode: Int = 0
  var errorDescription: String? { message }
  var details: [String: Any] { ["domain": domain, "nativeCode": nativeCode] }

  static func classify(_ error: Error) -> SystemSpeechError {
    if let error = error as? SystemSpeechError { return error }
    var current = error as NSError
    var seen = Set<ObjectIdentifier>()
    while seen.insert(ObjectIdentifier(current)).inserted {
      if current.domain == "kLSRErrorDomain", current.code == 201 {
        return SystemSpeechError(code: "speech_dictation_disabled", message: current.localizedDescription,
          domain: current.domain, nativeCode: current.code)
      }
      if current.domain == NSURLErrorDomain,
         [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
          NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorTimedOut].contains(current.code) {
        return SystemSpeechError(code: "speech_network_unavailable", message: current.localizedDescription,
          domain: current.domain, nativeCode: current.code)
      }
      guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
      current = underlying
    }
    let native = error as NSError
    return SystemSpeechError(code: "speech_recognition_failed", message: native.localizedDescription,
      domain: native.domain, nativeCode: native.code)
  }
}

// Audio ranges, not text equality, distinguish a revision from a real repeated phrase.
struct SystemSpeechSnapshots {
  struct Part {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    var separator: String = " "
    var utteranceStart: TimeInterval?
  }
  private var phrases: [Part] = []
  private var pending: [Part] = []
  var text: String {
    (phrases + pending).sorted { $0.start < $1.start }
      .reduce("") { $0 + $1.separator + $1.text }.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  mutating func update(text: String, start: TimeInterval, end: TimeInterval, committed: Bool) {
    update(parts: [Part(text: text, start: start, end: end)], committed: committed)
  }
  mutating func update(parts: [Part], committed: Bool, utteranceStart: TimeInterval? = nil) {
    var parts = parts.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    guard let start = parts.first?.start, let end = parts.last?.end else { return }
    let previous = phrases + pending
    let anchor = utteranceStart ?? start
    if let old = previous.first(where: { $0.start == start }) { parts[0].separator = old.separator }
    for index in parts.indices {
      parts[index].utteranceStart = parts[index].start >= anchor ? anchor :
        (previous.first(where: { $0.start == parts[index].start })?.utteranceStart ?? parts[index].start)
    }
    // Replace the entire revised utterance, even when its latest hypothesis is shorter.
    // A tail-only callback preserves earlier parts of a cumulative pending snapshot.
    var replacedAnchors: Set<TimeInterval> = [anchor]
    // Metadata may arrive only after partial results. Match the first audio segment
    // to transfer its provisional identity without treating a cumulative tail as a new prefix.
    var firstByUtterance: [TimeInterval: Part] = [:]
    for old in previous {
      guard let identity = old.utteranceStart else { continue }
      if old.start < (firstByUtterance[identity]?.start ?? .infinity) { firstByUtterance[identity] = old }
    }
    for (identity, old) in firstByUtterance {
      if old.start < parts[0].end && start < old.end { replacedAnchors.insert(identity) }
    }
    phrases = previous.filter {
      // A tail owns obsolete trailing words from an older cumulative snapshot,
      // even without metadata or when the revised result no longer overlaps them.
      let replacedTail = $0.start >= anchor && ($0.utteranceStart ?? anchor) <= anchor
      return !replacedTail && !($0.utteranceStart.map { replacedAnchors.contains($0) } ?? false)
        && !($0.start < end && start < $0.end) && $0.start != start
    }
    pending = []
    if committed { phrases += parts } else { pending = parts }
  }

}

enum SystemSpeechAccess {
  static func recognizer(_ identifier: String?) -> SFSpeechRecognizer? {
    guard let identifier, !identifier.isEmpty else { return SFSpeechRecognizer() }
    guard let locale = resolveLocale(identifier) else { return nil }
    return SFSpeechRecognizer(locale: locale)
  }

  static func resolveLocale(_ identifier: String, supported: Set<Locale> = SFSpeechRecognizer.supportedLocales(),
                            region: String? = Locale.current.regionCode) -> Locale? {
    let requested = Locale(identifier: identifier)
    func normalized(_ value: String) -> String {
      value.replacingOccurrences(of: "_", with: "-").lowercased()
    }
    if let exact = supported.first(where: { normalized($0.identifier) == normalized(identifier) }) { return exact }
    guard requested.regionCode == nil, let language = requested.languageCode else { return nil }
    func script(_ locale: Locale) -> String? {
      if let explicit = locale.scriptCode { return explicit }
      if #available(iOS 16.0, macOS 13.0, *) { return locale.language.script?.identifier }
      // Older Foundation cannot infer scripts. Cover the app's supported languages explicitly.
      if locale.languageCode == "zh" {
        return ["TW", "HK", "MO"].contains(locale.regionCode ?? "") ? "Hant" : "Hans"
      }
      return ["en": "Latn", "ru": "Cyrl", "de": "Latn", "fr": "Latn",
              "es": "Latn", "ar": "Arab"][locale.languageCode ?? ""]
    }
    let candidates = supported.filter {
      $0.languageCode == language && (requested.scriptCode == nil || script($0) == requested.scriptCode)
    }.sorted { $0.identifier < $1.identifier }
    let defaultRegion = requested.scriptCode == "Hant" ? "TW" :
      ["en": "US", "ru": "RU", "de": "DE", "fr": "FR", "es": "ES", "ar": "SA", "zh": "CN"][language]
    return candidates.first(where: { $0.regionCode == region })
      ?? candidates.first(where: { $0.regionCode == defaultRegion }) ?? candidates.first
  }

  static func speechStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "authorized"
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    default: return "denied"
    }
  }
  static func microphoneStatus() -> String {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return "authorized"
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    default: return "denied"
    }
  }
  static func check(_ locale: String?) -> [String: Any] {
    ["microphone": microphoneStatus(),
     "speech": speechStatus(SFSpeechRecognizer.authorizationStatus()),
     "available": recognizer(locale)?.isAvailable ?? false]
  }
  static func request(_ locale: String?, completion: @escaping ([String: Any]) -> Void) {
    func microphone() {
      if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
          DispatchQueue.main.async { completion(check(locale)) }
        }
      } else { completion(check(locale)) }
    }
    if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
      SFSpeechRecognizer.requestAuthorization { _ in DispatchQueue.main.async { microphone() } }
    } else { microphone() }
  }
  static func prepareStorage(_ path: String) throws {
    let root = try FileManager.default.url(for: .applicationSupportDirectory,
      in: .userDomainMask, appropriateFor: nil, create: false).resolvingSymlinksInPath().standardizedFileURL
    var directory = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
    guard path.hasPrefix("/"), directory.path.hasPrefix(root.path + "/") else {
      throw SystemSpeechError(code: "invalid_recording_storage", message: "Recording storage must be inside Application Support.")
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw SystemSpeechError(code: "invalid_recording_storage", message: "Recording storage directory does not exist.")
    }
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try directory.setResourceValues(values)
  }
}

/// Owns one transcription and its temporary files. Called on the main queue.
final class SystemSpeechTranscriber {
  typealias Completion = (Result<SystemSpeechTranscript, Error>) -> Void
  typealias Recognize = (URL, String?, Bool, @escaping Completion) -> (() -> Void)

  private let recognize: Recognize
  private var completion: Completion?
  private var cancelRecognition: (() -> Void)?
  private var requestID: UUID?
  private var temporaryDirectory: URL?
  private var chunks: [URL] = []
  private var transcripts: [SystemSpeechTranscript] = []

  init(recognize: @escaping Recognize = SystemSpeechTranscriber.recognizeFile) {
    self.recognize = recognize
  }

  func transcribe(url: URL, locale: String?, onDevice: Bool, completion: @escaping Completion) {
    guard self.completion == nil else {
      completion(.failure(SystemSpeechError(
        code: "speech_already_active", message: "System speech recognition is already active."
      )))
      return
    }
    self.completion = completion
    do {
      let file = try AVAudioFile(forReading: url)
      guard file.length > 0 else {
        throw SystemSpeechError(code: "empty_recording", message: "Recorded audio file is empty.")
      }
      // ponytail: fixed chunk boundaries; split at silence if boundary recognition needs improvement.
      let framesPerChunk = AVAudioFrameCount(file.processingFormat.sampleRate * 59)
      if file.length <= AVAudioFramePosition(framesPerChunk) {
        chunks = [url]
      } else {
        let directory = FileManager.default.temporaryDirectory
          .appendingPathComponent("pomodoist-speech-\(UUID().uuidString)")
        temporaryDirectory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: framesPerChunk) else {
          throw SystemSpeechError(code: "invalid_audio", message: "Cannot read recorded audio.")
        }
        while file.framePosition < file.length {
          try file.read(into: buffer, frameCount: framesPerChunk)
          guard buffer.frameLength > 0 else {
            throw SystemSpeechError(code: "invalid_audio", message: "Recorded audio ended unexpectedly.")
          }
          let chunk = directory.appendingPathComponent("\(chunks.count).wav")
          // Drain AVAudioFile's autorelease before Speech opens the completed WAV.
          try autoreleasepool {
            let output = try AVAudioFile(forWriting: chunk, settings: file.fileFormat.settings)
            try output.write(from: buffer)
            if #available(iOS 18.0, macOS 15.0, *) { output.close() }
          }
          chunks.append(chunk)
        }
      }
      recognizeNext(locale: locale, onDevice: onDevice)
    } catch {
      finish(.failure(error))
    }
  }

  func cancel() {
    guard completion != nil else { return }
    finish(.failure(SystemSpeechError(
      code: "speech_canceled", message: "System speech recognition was canceled."
    )))
  }

  private func recognizeNext(locale: String?, onDevice: Bool) {
    let id = UUID()
    requestID = id
    cancelRecognition = recognize(chunks[transcripts.count], locale, onDevice) { [weak self] outcome in
      // Apple may invoke callbacks on any queue, including after cancellation.
      DispatchQueue.main.async {
        guard let self, self.requestID == id else { return }
        switch outcome {
        case .failure(let error):
          self.finish(.failure(error))
        case .success(let transcript):
          guard !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.finish(.failure(SystemSpeechError(code: "empty_transcript", message: "System speech recognition returned no text.")))
            return
          }
          self.transcripts.append(transcript)
          if self.transcripts.count < self.chunks.count {
            self.recognizeNext(locale: locale, onDevice: onDevice)
          } else {
            let text = self.transcripts.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
              .filter { !$0.isEmpty }.joined(separator: " ")
            guard !text.isEmpty else {
              self.finish(.failure(SystemSpeechError(
                code: "empty_transcript", message: "System speech recognition returned no text."
              )))
              return
            }
            let confidences = self.transcripts.compactMap(\.confidence)
            self.finish(.success(SystemSpeechTranscript(
              text: text,
              confidence: confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)
            )))
          }
        }
      }
    }
  }

  private func finish(_ outcome: Result<SystemSpeechTranscript, Error>) {
    requestID = nil
    let callback = completion
    completion = nil
    let cancel = cancelRecognition
    cancelRecognition = nil
    if case .failure = outcome { cancel?() }
    if let directory = temporaryDirectory {
      try? FileManager.default.removeItem(at: directory)
    }
    temporaryDirectory = nil
    chunks = []
    transcripts = []
    callback?(outcome)
  }

  private static func recognizeFile(
    url: URL, locale: String?, onDevice: Bool, completion: @escaping Completion
  ) -> () -> Void {
    guard let recognizer = SystemSpeechAccess.recognizer(locale) else {
      completion(.failure(SystemSpeechError(code: "speech_locale_unsupported", message: "The requested speech language is unsupported.")))
      return {}
    }
    guard recognizer.isAvailable else {
      completion(.failure(SystemSpeechError(code: "speech_unavailable", message: "System speech recognition is currently unavailable.")))
      return {}
    }
    let request = SFSpeechURLRecognitionRequest(url: url)
    request.shouldReportPartialResults = true
    request.taskHint = .dictation
    request.requiresOnDeviceRecognition = onDevice && recognizer.supportsOnDeviceRecognition
    var snapshots = SystemSpeechSnapshots()
    var finished = false
    let task = recognizer.recognitionTask(with: request) { recognition, error in
      DispatchQueue.main.async {
        guard !finished else { return }
        if let recognition {
          let segments = recognition.bestTranscription.segments
          let formatted = recognition.bestTranscription.formattedString as NSString
          let parts = segments.enumerated().map { index, segment in
            // Keep punctuation between segments while retaining per-word audio ranges.
            let start = segment.substringRange.location
            let end = index + 1 < segments.count ? segments[index + 1].substringRange.location : formatted.length
            let text = formatted.substring(with: NSRange(location: start, length: max(0, end - start)))
              .trimmingCharacters(in: .whitespacesAndNewlines)
            let separator: String
            if index == 0 { separator = " " }
            else {
              let gapStart = NSMaxRange(segments[index - 1].substringRange)
              let gap = formatted.substring(with: NSRange(location: gapStart, length: max(0, start - gapStart)))
              separator = String(gap.reversed().prefix(while: { $0.isWhitespace }).reversed())
            }
            return SystemSpeechSnapshots.Part(text: text, start: segment.timestamp,
              end: segment.timestamp + segment.duration, separator: separator)
          }
          let metadata = recognition.speechRecognitionMetadata
          let finalLike = (metadata?.speechDuration ?? 0) > 0
          snapshots.update(parts: parts, committed: recognition.isFinal || finalLike,
            utteranceStart: finalLike ? metadata?.speechStartTimestamp : nil)
          if recognition.isFinal {
            finished = true
            completion(.success(SystemSpeechTranscript(text: snapshots.text,
              confidence: segments.isEmpty ? nil : segments.reduce(0.0) { $0 + Double($1.confidence) } / Double(segments.count))))
            return
          }
        }
        if let error {
          finished = true
          completion(.failure(SystemSpeechError.classify(error)))
        }
      }
    }
    return { finished = true; task.cancel() }
  }
}
