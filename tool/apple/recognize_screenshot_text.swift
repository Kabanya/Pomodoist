import Foundation
import Vision
import ImageIO
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
request.automaticallyDetectsLanguage = true
try VNImageRequestHandler(url: url).perform([request])
let texts = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
let data = try JSONSerialization.data(withJSONObject: texts, options: [.prettyPrinted, .withoutEscapingSlashes])
print(String(decoding: data, as: UTF8.self))
