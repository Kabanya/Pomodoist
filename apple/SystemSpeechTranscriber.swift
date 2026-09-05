import AVFoundation
import Speech

struct SystemSpeechTranscript {
  let text: String
  let confidence: Double?
}

struct SystemSpeechError: LocalizedError {
  let code: String
  let message: String
  var errorDescription: String? { message }
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
      if onDevice || file.length <= AVAudioFramePosition(framesPerChunk) {
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
    let recognizer = locale.flatMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
      ?? SFSpeechRecognizer()
    guard let recognizer, recognizer.isAvailable,
          !onDevice || recognizer.supportsOnDeviceRecognition else {
      completion(.failure(SystemSpeechError(
        code: "speech_unavailable", message: "System speech recognition is currently unavailable."
      )))
      return {}
    }
    let request = SFSpeechURLRecognitionRequest(url: url)
    request.shouldReportPartialResults = false
    request.taskHint = .dictation
    request.requiresOnDeviceRecognition = onDevice
    let task = recognizer.recognitionTask(with: request) { recognition, error in
      if let recognition, recognition.isFinal {
        let segments = recognition.bestTranscription.segments
        completion(.success(SystemSpeechTranscript(
          text: recognition.bestTranscription.formattedString,
          confidence: segments.isEmpty ? nil
            : segments.reduce(0.0) { $0 + Double($1.confidence) } / Double(segments.count)
        )))
      } else if let error {
        completion(.failure(error))
      }
    }
    return { task.cancel() }
  }
}
