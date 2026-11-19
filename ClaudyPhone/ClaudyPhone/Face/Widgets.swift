// Widgets.swift: the carousel screens besides the face: screen light, timer, radar, level
// (real distance comes with LiDAR in phase B5) and crosshair.
import SwiftUI

/// The whole screen glows white or any colour, as a soft fill light.
struct LightWidget: View {
    @Environment(AppState.self) private var state
    @AppStorage("lightHue") private var hue = 0.1
    @AppStorage("lightWhite") private var white = true

    var body: some View {
        ZStack(alignment: .bottom) {
            (state.lightColor ?? (white ? Color.white : Color(hue: hue, saturation: 0.55, brightness: 1)))
                .allowsHitTesting(false)
            HStack(spacing: 16) {
                Button(white ? "Colour" : "White") {
                    white.toggle()
                    state.touched()
                }
                .buttonStyle(.borderedProminent)
                .tint(.black.opacity(0.6))
                if !white {
                    Slider(value: $hue, in: 0...1) { _ in state.touched() }
                        .tint(.black.opacity(0.5))
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal, 30)
            .padding(.bottom, 90)
        }
    }
}

/// A countdown ring with quick buttons. Buzzes and wakes Claudy at zero.
struct TimerWidget: View {
    @Environment(AppState.self) private var state
    var color: Color

    var body: some View {
        VStack(spacing: 24) {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let left = max(0, state.timerEnd?.timeIntervalSince(context.date) ?? 0)
                let fraction = state.timerTotal > 0 ? left / state.timerTotal : 0
                ZStack {
                    Circle().stroke(color.opacity(0.15), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(state.timerEnd == nil ? "Timer" : Self.format(left))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .frame(width: 190, height: 190)
            }
            .allowsHitTesting(false)
            HStack(spacing: 10) {
                ForEach([1.0, 5, 10, 25], id: \.self) { minutes in
                    Button("\(Int(minutes)) min") { state.startTimer(minutes: minutes) }
                        .buttonStyle(.bordered)
                        .tint(color)
                }
                if state.timerEnd != nil {
                    Button("Stop") { state.cancelTimer() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
            }
        }
    }

    static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A radar sweep. The distance reading is a placeholder until phase B5 adds LiDAR.
struct RadarWidget: View {
    var color: Color

    var body: some View {
        VStack(spacing: 16) {
            TimelineView(.animation) { context in
                let angle = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 3) / 3 * 360
                Canvas { gc, size in
                    let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) / 2
                    for ring in 1...3 {
                        let r = radius * CGFloat(ring) / 3
                        let box = CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)
                        gc.stroke(Path(ellipseIn: box), with: .color(color.opacity(0.25)), lineWidth: 1.5)
                    }
                    for k in 0..<12 {   // the sweep and its fading trail
                        var wedge = Path()
                        wedge.move(to: centre)
                        wedge.addArc(center: centre, radius: radius,
                                     startAngle: .degrees(angle - Double(k + 1) * 5),
                                     endAngle: .degrees(angle - Double(k) * 5), clockwise: false)
                        wedge.closeSubpath()
                        gc.fill(wedge, with: .color(color.opacity(0.45 * (1 - Double(k) / 12))))
                    }
                }
                .frame(width: 210, height: 210)
            }
            Text("-- cm")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Real distance arrives with LiDAR in phase B5")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
        }
        .allowsHitTesting(false)
    }
}

/// An on-screen crosshair you can drag. From phase B2 it marks what Claude should look at.
struct CrosshairWidget: View {
    @Environment(AppState.self) private var state
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Circle().stroke(color, lineWidth: 2).frame(width: 60, height: 60)
                Rectangle().fill(color).frame(width: 2, height: 90)
                Rectangle().fill(color).frame(width: 90, height: 2)
                Circle().fill(color).frame(width: 6, height: 6)
            }
            .frame(width: 110, height: 110)
            .contentShape(Rectangle())
            .position(x: state.crosshair.x * geo.size.width, y: state.crosshair.y * geo.size.height)
            .gesture(
                DragGesture(coordinateSpace: .named("crosshair"))
                    .onChanged { drag in
                        state.touched()
                        state.crosshair = CGPoint(
                            x: min(max(drag.location.x / geo.size.width, 0.05), 0.95),
                            y: min(max(drag.location.y / geo.size.height, 0.05), 0.95))
                    }
            )
            Text("Drag the crosshair. From phase B2 it marks what to look at.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 90)
                .allowsHitTesting(false)
        }
        .coordinateSpace(.named("crosshair"))
    }
}

/// A bubble level. Lying flat: a bubble that centres when level. Standing up: a tilt line.
struct LevelWidget: View {
    @Environment(AppState.self) private var state
    var color: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20)) { _ in
            let g = state.motion.gravity
            let flat = abs(g.z) > 0.7
            VStack(spacing: 22) {
                if flat {
                    let tilt = acos(min(1, abs(g.z))) * 180 / .pi
                    ZStack {
                        Circle().stroke(color.opacity(0.3), lineWidth: 2).frame(width: 220, height: 220)
                        Circle().stroke(color.opacity(0.5), lineWidth: 2).frame(width: 40, height: 40)
                        Circle()
                            .fill(tilt < 1 ? Color.green : color)
                            .frame(width: 34, height: 34)
                            .offset(x: -g.x * 300, y: g.y * 300)
                            .animation(.easeOut(duration: 0.1), value: g.x)
                    }
                    .frame(width: 220, height: 220)
                    .clipShape(Circle())
                    reading(tilt)
                } else {
                    let roll = atan2(g.x, -g.y) * 180 / .pi
                    ZStack {
                        Rectangle().fill(color.opacity(0.25)).frame(width: 260, height: 2)
                        Rectangle()
                            .fill(abs(roll) < 1 ? Color.green : color)
                            .frame(width: 260, height: 4)
                            .rotationEffect(.degrees(-roll))
                    }
                    .frame(height: 220)
                    reading(abs(roll))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func reading(_ degrees: Double) -> some View {
        Text(String(format: "%.1f°", degrees))
            .font(.system(size: 44, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(degrees < 1 ? .green : .white)
    }
}
