// FaceView.swift: the main screen. Shows the current widget (the face by default), listens for
// gestures, dims when idle, and opens settings on a two-finger hold.
import SwiftUI

struct FaceView: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("eyeColor") private var eyeHex = Color.defaultEyeHex
    @AppStorage("motionSensitivity") private var sensitivity = 0.5
    @State private var dotsShownAt: Date?

    private var eyeColor: Color { Color(hex: eyeHex) ?? .cyan }

    var body: some View {
        @Bindable var state = state
        ZStack {
            Color.black
            TouchLayer(onTap: state.tap, onSwipe: state.swipe, onPet: state.pet,
                       onTwoFingerHold: state.openSettings)
            currentWidget
                .transition(.opacity)
            if state.widget != .face {
                EyesView(color: eyeColor, compact: true)
                    .frame(width: 110, height: 70)
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .allowsHitTesting(false)
            }
            if dotsShownAt != nil {
                PageDots(current: state.widget)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 30)
                    .allowsHitTesting(false)
            }
            Color.black
                .opacity(state.isDimmed ? 0.7 : 0)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .vertical)   // swipes near the edges go to Claudy first
        .sheet(isPresented: $state.showSettings) {
            SettingsView()
                .environment(state)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            state.motion.sensitivity = sensitivity
            state.start()
        }
        .onChange(of: sensitivity) { _, value in state.motion.sensitivity = value }
        .onChange(of: state.widget) { flashDots() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { state.motion.start() }
            if phase == .background { state.motion.stop() }
        }
    }

    @ViewBuilder private var currentWidget: some View {
        switch state.widget {
        case .face: EyesView(color: eyeColor).allowsHitTesting(false)
        case .light: LightWidget()
        case .timer: TimerWidget(color: eyeColor)
        case .radar: RadarWidget(color: eyeColor)
        case .crosshair: CrosshairWidget(color: eyeColor)
        }
    }

    private func flashDots() {
        let now = Date()
        withAnimation(.easeOut(duration: 0.2)) { dotsShownAt = now }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if dotsShownAt == now { withAnimation(.easeIn(duration: 0.4)) { dotsShownAt = nil } }
        }
    }
}

/// The little row of dots that says which widget you are on.
struct PageDots: View {
    let current: Widget

    var body: some View {
        VStack(spacing: 8) {
            Text(current.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 8) {
                ForEach(Widget.allCases) { w in
                    Capsule()
                        .fill(.white.opacity(w == current ? 0.9 : 0.3))
                        .frame(width: w == current ? 22 : 8, height: 8)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.45), in: Capsule())
    }
}
