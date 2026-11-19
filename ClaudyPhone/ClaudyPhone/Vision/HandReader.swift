// HandReader.swift: finds hands in a camera frame with Apple's Vision framework (on the phone) and
// recognises three gestures: thumbs up (take a photo), open palm (pause watching), pointing (this one).
import CoreVideo
import Vision

struct HandSighting: Sendable {
    var boxes: [CGRect]          // 0...1, top-left origin, one per hand
    var gesture: String?         // "thumbs_up", "open_palm", "point", or nil
    var fingertip: CGPoint?      // index fingertip when pointing, 0...1 top-left origin
}

final class HandReader {
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()

    func read(_ pixels: CVPixelBuffer) -> HandSighting {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up)
        try? handler.perform([request])
        var sighting = HandSighting(boxes: [], gesture: nil, fingertip: nil)
        for hand in request.results ?? [] {
            guard let points = try? hand.recognizedPoints(.all) else { continue }
            let seen = points.values.filter { $0.confidence > 0.3 }
            guard seen.count >= 6 else { continue }
            let xs = seen.map(\.location.x), ys = seen.map(\.location.y)
            sighting.boxes.append(CGRect(x: xs.min()!, y: 1 - ys.max()!,
                                         width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!))
            if sighting.gesture == nil, let (gesture, tip) = Self.gesture(points) {
                sighting.gesture = gesture
                sighting.fingertip = tip
            }
        }
        return sighting
    }

    /// Simple geometry: a finger is "out" when its tip is much farther from the wrist than its knuckle.
    private static func gesture(_ p: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint])
        -> (String, CGPoint?)? {
        func point(_ j: VNHumanHandPoseObservation.JointName) -> CGPoint? {
            guard let v = p[j], v.confidence > 0.3 else { return nil }
            return v.location
        }
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        guard let wrist = point(.wrist) else { return nil }
        func out(_ tip: VNHumanHandPoseObservation.JointName, _ knuckle: VNHumanHandPoseObservation.JointName) -> Bool? {
            guard let t = point(tip), let k = point(knuckle) else { return nil }
            return distance(t, wrist) > distance(k, wrist) * 1.6
        }
        guard let index = out(.indexTip, .indexMCP), let middle = out(.middleTip, .middleMCP),
              let ring = out(.ringTip, .ringMCP), let little = out(.littleTip, .littleMCP),
              let thumbTip = point(.thumbTip), let thumbBase = point(.thumbCMC) else { return nil }
        let thumbOut = distance(thumbTip, wrist) > distance(thumbBase, wrist) * 1.8

        if index && middle && ring && little && thumbOut { return ("open_palm", nil) }
        if index && !middle && !ring && !little, let tip = point(.indexTip) {
            return ("point", CGPoint(x: tip.x, y: 1 - tip.y))
        }
        // Thumbs up: other fingers curled and the thumb tip clearly above everything else.
        if !index && !middle && !ring && !little && thumbOut,
           let indexKnuckle = point(.indexMCP), thumbTip.y > indexKnuckle.y + 0.05, thumbTip.y > wrist.y {
            return ("thumbs_up", nil)
        }
        return nil
    }
}
