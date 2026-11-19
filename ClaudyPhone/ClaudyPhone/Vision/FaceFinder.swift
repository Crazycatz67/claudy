// FaceFinder.swift: finds the biggest face in a camera frame with Apple's Vision framework,
// entirely on the phone. Returns its centre as -1...1 (+x right, +y down).
import CoreVideo
import Vision

final class FaceFinder {
    private let request = VNDetectFaceRectanglesRequest()

    func centre(in pixels: CVPixelBuffer) -> CGPoint? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up)
        try? handler.perform([request])
        guard let face = (request.results ?? []).max(by: { $0.boundingBox.width < $1.boundingBox.width })
        else { return nil }
        // Vision measures from the bottom-left corner, 0...1.
        let box = face.boundingBox
        return CGPoint(x: box.midX * 2 - 1, y: 1 - box.midY * 2)
    }
}
