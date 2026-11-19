// Haptics.swift: Claudy's haptic vocabulary (tap, click, heartbeat, attention, stop, purr)
// made with Core Haptics, with a simple fallback if Core Haptics is unavailable.
import CoreHaptics
import UIKit

enum HapticPattern: String, CaseIterable, Identifiable {
    case tap, click, heartbeat, attention, stop, purr
    var id: String { rawValue }
    var meaning: String {
        switch self {
        case .tap: "heard you"
        case .click: "photo taken"
        case .heartbeat: "thinking"
        case .attention: "look at me"
        case .stop: "stop / cancelled"
        case .purr: "petted"
        }
    }
}

@MainActor
final class Haptics {
    private var engine: CHHapticEngine?
    private let hasHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    func prepare() {
        guard hasHaptics, engine == nil else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
    }

    func play(_ pattern: HapticPattern) {
        prepare()
        guard let engine else { fallback(pattern); return }
        do {
            try engine.start()
            let player = try engine.makePlayer(with: try Self.make(pattern))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback(pattern)
        }
    }

    private func fallback(_ pattern: HapticPattern) {
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch pattern {
        case .tap: style = .light
        case .click: style = .rigid
        case .heartbeat, .purr: style = .soft
        case .attention, .stop: style = .heavy
        }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private static func make(_ pattern: HapticPattern) throws -> CHHapticPattern {
        func hit(_ time: Double, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: time)
        }
        func buzz(_ time: Double, _ length: Double, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: time, duration: length)
        }

        switch pattern {
        case .tap:
            return try CHHapticPattern(events: [hit(0, 0.55, 0.5)], parameters: [])
        case .click:      // crisp shutter
            return try CHHapticPattern(events: [hit(0, 1, 1), hit(0.05, 0.45, 0.9)], parameters: [])
        case .heartbeat:  // soft lub-dub
            return try CHHapticPattern(events: [hit(0, 0.75, 0.1), hit(0.2, 0.45, 0.05)], parameters: [])
        case .attention:  // two strong sharp pulses
            return try CHHapticPattern(events: [hit(0, 1, 0.8), hit(0.13, 1, 0.8)], parameters: [])
        case .stop:       // one long firm buzz
            return try CHHapticPattern(events: [buzz(0, 0.6, 1, 0.35)], parameters: [])
        case .purr:       // a low rumble that flutters up and down
            let length = 1.0
            let times = Array(stride(from: 0.0, through: length, by: 0.045))
            // A curve may hold at most 16 points, so split the flutter into several curves.
            let curves = stride(from: 0, to: times.count, by: 16).map { first in
                let chunk = times[first..<min(first + 16, times.count)]
                let start = chunk.first ?? 0
                let points = chunk.enumerated().map { offset, t in
                    CHHapticParameterCurve.ControlPoint(relativeTime: t - start,
                                                        value: (first + offset) % 2 == 0 ? 1.0 : 0.25)
                }
                return CHHapticParameterCurve(parameterID: .hapticIntensityControl,
                                              controlPoints: points, relativeTime: start)
            }
            return try CHHapticPattern(events: [buzz(0, length, 0.6, 0.05)], parameterCurves: curves)
        }
    }
}
