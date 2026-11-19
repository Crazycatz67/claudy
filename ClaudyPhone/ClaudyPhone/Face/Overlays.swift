// Overlays.swift: things drawn on top of the face: the Inspect mode controls, the brain badge
// ("brain offline" / "Mac sees"), captions of what Claudy says, and the yes/no card.
import SwiftUI

/// Inspect mode: the face shrinks to a corner bubble, with lens buttons and the tap marker.
struct InspectOverlay: View {
    @Environment(AppState.self) private var state
    var color: Color
    var size: CGSize

    var body: some View {
        ZStack {
            if state.measuring { MeasureLayer(color: color, size: size) }
            if let mark = state.pointMark {
                let picture = size.cameraPictureRect(aspect: state.pictureAspect)
                ZStack {
                    Circle().stroke(color, lineWidth: 3).frame(width: 56, height: 56)
                    Circle().fill(color).frame(width: 8, height: 8)
                }
                .shadow(color: .black.opacity(0.6), radius: 4)
                .position(x: picture.minX + mark.x * picture.width, y: picture.minY + mark.y * picture.height)
                .allowsHitTesting(false)
                .transition(.scale.combined(with: .opacity))
            }

            EyesView(color: color, compact: true)
                .frame(width: 120, height: 76)
                .padding(10)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(.top, 50)
                .padding(.trailing, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false)

            VStack(spacing: 14) {
                if !state.seenText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Reading", systemImage: "text.viewfinder")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(color)
                        ForEach(state.seenText, id: \.self) { line in
                            Text(line).font(.system(.callout, design: .monospaced)).foregroundStyle(.white)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: 360, alignment: .leading)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .allowsHitTesting(false)
                }
                if state.torchIsOn {
                    Label("Flashlight on (it was dark)", systemImage: "flashlight.on.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: Capsule())
                        .allowsHitTesting(false)
                }
                if state.lenses.count > 1 {
                    HStack(spacing: 10) {
                        ForEach(state.lenses, id: \.self) { lens in
                            let selected = abs(state.zoom - lens.zoom) < 0.05
                            Button(lens.name) { state.selectLens(lens) }
                                .font(.footnote.weight(.semibold))
                                .frame(width: 48, height: 48)
                                .background(.black.opacity(selected ? 0.75 : 0.45), in: Circle())
                                .foregroundStyle(selected ? color : .white)
                        }
                    }
                }
                HStack(spacing: 12) {
                    Button { state.setMode(.buddy) } label: {
                        Label("Face", systemImage: "face.smiling")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black.opacity(0.6))
                    Button { state.setMeasuring(!state.measuring) } label: {
                        Label(state.measuring ? "Done" : "Measure", systemImage: "ruler")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(state.measuring ? color.opacity(0.8) : .black.opacity(0.6))
                    Text(state.measuring ? "Drag a box over the part" : "Tap anything to ask what it is")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 40)
        }
    }
}

/// LiDAR measuring: live distance to the centre, and drag a box to get a size.
struct MeasureLayer: View {
    @Environment(AppState.self) private var state
    var color: Color
    var size: CGSize
    @State private var start: CGPoint?
    @State private var end: CGPoint?
    @State private var lastBox: CGRect?

    var body: some View {
        let picture = size.cameraPictureRect(aspect: state.pictureAspect)
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { drag in
                            if start == nil { start = drag.startLocation }
                            end = drag.location
                        }
                        .onEnded { _ in
                            if let box = screenBox {
                                lastBox = box
                                state.measure(box: CGRect(x: (box.minX - picture.minX) / picture.width,
                                                          y: (box.minY - picture.minY) / picture.height,
                                                          width: box.width / picture.width,
                                                          height: box.height / picture.height))
                            }
                            start = nil
                            end = nil
                        }
                )

            // Centre dot with the live distance.
            VStack(spacing: 6) {
                Image(systemName: "plus").font(.title2.weight(.light)).foregroundStyle(color)
                Text(state.distanceCM.map { String(format: "%.0f cm", $0) } ?? "-- cm")
                    .font(.system(.headline, design: .rounded)).monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
            }
            .position(x: picture.midX, y: picture.midY + 14)
            .allowsHitTesting(false)

            if let box = screenBox ?? lastBox {
                Rectangle()
                    .stroke(color, style: StrokeStyle(lineWidth: 2, dash: screenBox == nil ? [] : [6, 4]))
                    .frame(width: box.width, height: box.height)
                    .position(x: box.midX, y: box.midY)
                    .allowsHitTesting(false)
                if screenBox == nil, let m = state.measurement {
                    Text(String(format: "%.0f × %.0f mm", m.widthMM, m.heightMM))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold)).monospacedDigit()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(color.opacity(0.85), in: Capsule())
                        .foregroundStyle(.black)
                        .position(x: box.midX, y: max(20, box.minY - 16))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var screenBox: CGRect? {
        guard let start, let end else { return nil }
        return CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                      width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

/// Small pill in the top-left corner: brain offline, connecting, or "Mac sees" while sharing.
struct BrainBadge: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            switch state.link.status {
            case .off:
                EmptyView()
            case .searching, .connecting:
                pill("looking for brain", dot: .yellow)
            case .offline:
                pill("brain offline", dot: .orange)
            case .connected:
                if state.cameraOn && state.shareEnabled {
                    pill("Mac sees", dot: .green)
                } else {
                    pill("brain", dot: .green)
                }
            }
        }
        .padding(.top, 52)
        .padding(.leading, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.3), value: state.link.status)
    }

    private func pill(_ text: String, dot: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(text).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.5), in: Capsule())
    }
}

/// What Claudy says, shown as text at the bottom (captions and quiet mode).
struct CaptionView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let caption = state.caption {
            Text(caption)
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, state.mode == .inspect ? 150 : 90)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// The yes/no card: nothing runs on the Mac until you answer.
struct ConfirmCardView: View {
    @Environment(AppState.self) private var state
    let card: ConfirmCard

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 18) {
                Text("Run this on your Mac?")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(card.text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 14) {
                    Button("No") { state.answerConfirm(false) }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    Button("Yes, run it") { state.answerConfirm(true) }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(24)
        }
        .transition(.opacity)
    }
}
