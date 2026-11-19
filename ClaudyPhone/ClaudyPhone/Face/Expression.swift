// Expression.swift: Claudy's moods, and what each one does to the eyes (shape, size, colour).
import SwiftUI

/// The numbers that shape the eyes for one mood.
struct EyeLook {
    var openness: CGFloat = 1     // 1 = fully open, near 0 = a thin line
    var happy: CGFloat = 0        // 0...1, lifts the bottom into a smiling squint
    var slant: CGFloat = 0        // > 0 cross (inner corners down), < 0 worried (outer corners down)
    var scale: CGFloat = 1
    var bias: CGPoint = .zero     // extra look direction, e.g. up and to the side when thinking
    var dim: Double = 1           // brightness
}

enum Expression: String, CaseIterable, Identifiable {
    case idle, listening, thinking, happy, concerned, warning, sleeping, petted, dizzy

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Reactions last a moment, then the face goes back to its mood.
    var isReaction: Bool { self == .petted || self == .dizzy }

    var eye: EyeLook {
        switch self {
        case .idle: EyeLook()
        case .listening: EyeLook(openness: 1.08, scale: 1.08)
        case .thinking: EyeLook(openness: 0.72, slant: -0.25, bias: CGPoint(x: 0.5, y: -0.7))
        case .happy: EyeLook(happy: 0.55)
        case .concerned: EyeLook(openness: 0.85, slant: -0.6)
        case .warning: EyeLook(openness: 0.8, slant: 0.7, scale: 1.05)
        case .sleeping: EyeLook(openness: 0.06, dim: 0.35)
        case .petted: EyeLook(openness: 0.9, happy: 0.85, scale: 1.04)
        case .dizzy: EyeLook(openness: 0.7, scale: 0.95)
        }
    }

    /// Mood colours: blue when listening, amber when concerned, red for warnings.
    func color(base: Color) -> Color {
        switch self {
        case .listening: Color(red: 0.35, green: 0.7, blue: 1)
        case .concerned: Color(red: 1, green: 0.7, blue: 0.2)
        case .warning: Color(red: 1, green: 0.25, blue: 0.25)
        default: base
        }
    }
}
