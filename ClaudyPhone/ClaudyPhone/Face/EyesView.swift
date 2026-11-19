// EyesView.swift: draws Claudy's two eyes for the current mood, with blinking, drifting, glow and blush.
import SwiftUI

struct EyesView: View {
    @Environment(AppState.self) private var state
    var color: Color
    var compact = false   // small version shown in the corner on other widgets

    var body: some View {
        let mood = state.shown
        let shape = mood.eye
        let tint = mood.color(base: color)
        GeometryReader { geo in
            let eyeW = min(geo.size.width * 0.27, geo.size.height * 0.28)
            let eyeH = eyeW * 1.35
            let open = shape.openness * state.blink
            let shift = compact ? .zero : state.burnInShift
            HStack(spacing: eyeW * 0.6) {
                eye(mirrored: false, open: open, shape: shape, w: eyeW, h: eyeH, tint: tint, blush: mood == .petted)
                eye(mirrored: true, open: open, shape: shape, w: eyeW, h: eyeH, tint: tint, blush: mood == .petted)
            }
            .scaleEffect(shape.scale)
            .offset(x: (state.look.x + shape.bias.x) * eyeW * 0.35 + shift.width,
                    y: (state.look.y + shape.bias.y) * eyeH * 0.2 + shift.height)
            .opacity(shape.dim)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func eye(mirrored: Bool, open: CGFloat, shape: EyeLook, w: CGFloat, h: CGFloat,
                     tint: Color, blush: Bool) -> some View {
        ZStack {
            EyeShape(openness: open, happy: shape.happy, slant: shape.slant, mirrored: mirrored)
                .fill(tint)
                .shadow(color: tint.opacity(0.7), radius: compact ? 4 : 18)
            if blush {
                Ellipse()
                    .fill(Color.pink.opacity(0.45))
                    .frame(width: w * 0.7, height: h * 0.16)
                    .blur(radius: compact ? 2 : 6)
                    .offset(x: mirrored ? w * 0.2 : -w * 0.2, y: h * 0.5)
            }
        }
        .frame(width: w, height: h)
    }
}

/// One eye: a rounded block. "happy" cuts the bottom into a smile, "slant" cuts a lid off the top.
/// All three numbers animate smoothly between moods.
struct EyeShape: Shape {
    var openness: CGFloat
    var happy: CGFloat
    var slant: CGFloat
    var mirrored: Bool   // false = left eye (inner corner on its right)

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(openness, AnimatablePair(happy, slant)) }
        set {
            openness = newValue.first
            happy = newValue.second.first
            slant = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let h = max(rect.height * openness, rect.height * 0.05)
        let eye = CGRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h)
        var path = Path(roundedRect: eye, cornerRadius: min(rect.width, h) * 0.45)

        if happy > 0.01 {
            let cut = CGRect(x: eye.minX - eye.width * 0.2, y: eye.maxY - eye.height * happy * 0.9,
                             width: eye.width * 1.4, height: eye.height * 1.3)
            path = path.subtracting(Path(ellipseIn: cut))
        }

        if abs(slant) > 0.01 {
            let depth = eye.height * 0.6 * abs(slant)
            let inner = mirrored ? eye.minX : eye.maxX
            let outer = mirrored ? eye.maxX : eye.minX
            let low = slant > 0 ? inner : outer      // which corner the lid comes down on
            let high = slant > 0 ? outer : inner
            var lid = Path()
            lid.move(to: CGPoint(x: high, y: eye.minY - 1))
            lid.addLine(to: CGPoint(x: low, y: eye.minY + depth))
            lid.addLine(to: CGPoint(x: low, y: eye.minY - 100))
            lid.addLine(to: CGPoint(x: high, y: eye.minY - 100))
            lid.closeSubpath()
            path = path.subtracting(lid)
        }
        return path
    }
}
