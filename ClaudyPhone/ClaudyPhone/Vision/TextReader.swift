// TextReader.swift: reads printed text (labels, part numbers) in a camera frame, on the phone and
// offline, with Apple's Vision framework. Used in Inspect mode.
import CoreVideo
import Vision

final class TextReader {
    private let request: VNRecognizeTextRequest = {
        let r = VNRecognizeTextRequest()
        r.recognitionLevel = .fast          // fast enough to feel instant
        r.usesLanguageCorrection = false    // part numbers are not words
        r.minimumTextHeight = 0.02
        return r
    }()

    /// The clearest lines, biggest first, at most `limit`.
    func read(_ pixels: CVPixelBuffer, limit: Int = 4) -> [String] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up)
        try? handler.perform([request])
        return (request.results ?? [])
            .compactMap { obs -> (String, CGFloat)? in
                guard let best = obs.topCandidates(1).first, best.confidence > 0.4 else { return nil }
                let text = best.string.trimmingCharacters(in: .whitespaces)
                return text.count >= 2 ? (text, obs.boundingBox.height) : nil
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
