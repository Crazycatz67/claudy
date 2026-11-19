// FaceView.swift: the main screen. Buddy mode shows the current widget (the face by default);
// Inspect mode shows the back camera with the face in a corner bubble. Also shows the brain badge,
// captions and the yes/no card, listens for gestures, dims when idle, and opens settings.
import SwiftUI

struct FaceView: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("eyeColor") private var eyeHex = Color.defaultEyeHex
    @AppStorage("motionSensitivity") private var sensitivity = 0.5
    @AppStorage("followMe") private var followMe = false
    @AppStorage("shareWithMac") private var shareWithMac = false
    @AppStorage("macAddress") private var macAddress = ""
    @AppStorage("handGestures") private var handGestures = true
    @AppStorage("readText") private var readText = true
    @AppStorage("autoTorch") private var autoTorch = true
    @State private var dotsShownAt: Date?

    private var eyeColor: Color { Color(hex: eyeHex) ?? .cyan }
    @AppStorage("wakeWord") private var wakeWord = false
    @AppStorage("digitalFollow") private var digitalFollow = false
    private var cameraOptions: [Bool] { [handGestures, readText, autoTorch, digitalFollow] }
    private var inspecting: Bool { state.mode == .inspect && state.isAwake }

    var body: some View {
        @Bindable var state = state
        GeometryReader { geo in
            ZStack {
                Color.black
                if inspecting {
                    CameraPreview(session: state.camera.session)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                TouchLayer(onTap: { tapped(at: $0, in: geo.size) }, onSwipe: state.swipe,
                           onPet: state.pet, onTwoFingerHold: state.openSettings,
                           onPinch: { if inspecting { state.pinch(by: $0) } },
                           onHold: { $0 ? state.startTalking() : state.finishTalking() })
                if inspecting {
                    InspectOverlay(color: eyeColor, size: geo.size)
                } else {
                    currentWidget.transition(.opacity)
                    if state.widget != .face { cornerEyes }
                }
                if dotsShownAt != nil && !inspecting {
                    PageDots(current: state.widget)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 30)
                        .allowsHitTesting(false)
                }
                BrainBadge()
                CaptionView()
                if let card = state.confirmCard { ConfirmCardView(card: card) }
                Color.black
                    .opacity(state.isDimmed ? 0.7 : 0)
                    .allowsHitTesting(false)
            }
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
            apply(followMe: followMe)
            apply(share: shareWithMac)
        }
        .onChange(of: sensitivity) { _, value in state.motion.sensitivity = value }
        .onChange(of: followMe) { _, on in apply(followMe: on) }
        .onChange(of: shareWithMac) { _, on in apply(share: on) }
        .onChange(of: macAddress) { _, address in state.link.restart(manualAddress: address) }
        .onChange(of: cameraOptions) { state.updateCamera() }
        .onChange(of: wakeWord) { state.updateWakeWord() }
        .onChange(of: state.widget) { flashDots() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { state.motion.start() }
            if phase == .background { state.motion.stop() }
            state.setSceneActive(phase == .active)
        }
    }

    @ViewBuilder private var currentWidget: some View {
        switch state.widget {
        case .face: EyesView(color: eyeColor).allowsHitTesting(false)
        case .light: LightWidget()
        case .timer: TimerWidget(color: eyeColor)
        case .radar: RadarWidget(color: eyeColor)
        case .level: LevelWidget(color: eyeColor)
        case .crosshair: CrosshairWidget(color: eyeColor)
        }
    }

    private var cornerEyes: some View {
        EyesView(color: eyeColor, compact: true)
            .frame(width: 110, height: 70)
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .allowsHitTesting(false)
    }

    /// In Inspect mode a tap points at that spot; otherwise it is a normal tap.
    private func tapped(at location: CGPoint, in size: CGSize) {
        guard inspecting else { state.tap(); return }
        let picture = size.cameraPictureRect(aspect: state.pictureAspect)
        guard picture.contains(location) else { state.tap(); return }
        state.point(at: CGPoint(x: (location.x - picture.minX) / picture.width,
                                y: (location.y - picture.minY) / picture.height))
    }

    /// Switches flip themselves back off if iOS camera permission is refused.
    private func apply(followMe on: Bool) {
        Task { if await !state.setFollow(on) { followMe = false } }
    }

    private func apply(share on: Bool) {
        Task { if await !state.setShare(on) { shareWithMac = false } }
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
