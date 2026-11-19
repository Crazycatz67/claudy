// AppState.swift: Claudy's shared state and behaviour: awake or asleep, mood, blinking,
// eye drift, idle dimming, reactions (petting, shaking) and the timer.
import AVFoundation
import SwiftUI
import Observation

/// The screens you swipe between. The face is always first.
enum Widget: Int, CaseIterable, Identifiable {
    case face, light, timer, radar, crosshair
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .face: "Face"
        case .light: "Light"
        case .timer: "Timer"
        case .radar: "Radar"
        case .crosshair: "Crosshair"
        }
    }
}

@MainActor
@Observable
final class AppState {
    private(set) var isAwake = true
    private(set) var expression: Expression = .idle
    private(set) var reaction: Expression?          // short reactions on top of the mood
    var widget: Widget = .face
    private(set) var isDimmed = false
    private(set) var blink: CGFloat = 1             // 1 = open, near 0 = mid-blink
    var look: CGPoint = .zero          // where the eyes point, -1...1
    private(set) var burnInShift: CGSize = .zero    // tiny slow shift so pixels don't burn in
    private(set) var timerEnd: Date?
    private(set) var timerTotal: TimeInterval = 0
    private(set) var lastEvent = "started"
    var showSettings = false
    var crosshair = CGPoint(x: 0.5, y: 0.5)

    // Camera and Mac brain (see AppState+Brain.swift)
    var mode: CameraMode = .buddy
    var cameraOn = false                 // camera running (iOS green dot on)
    var cameraSide: CameraSide?
    var seesFace = false
    var faceChecksPerSecond = 0
    var photoFlash = false               // eyes flash red while a frame goes to Claude
    var caption: String?                 // what Claudy last said, shown as text
    var confirmCard: ConfirmCard?        // yes/no card before the Mac runs anything
    var lenses: [CameraService.Lens] = []
    var zoom: CGFloat = 1
    var pointMark: CGPoint?              // where you tapped in Inspect mode (0...1)
    var lightColor: Color?               // screen light set by the Mac
    var isListening = false              // microphone on (hold to talk)
    var heard = ""                       // words heard so far

    @ObservationIgnored let haptics = Haptics()
    @ObservationIgnored let motion = MotionSensor()
    @ObservationIgnored let camera = CameraService()
    @ObservationIgnored let link = BrainLink()
    @ObservationIgnored let listener = Listener()
    @ObservationIgnored let speaker = Speaker()
    @ObservationIgnored var followEnabled = false
    var shareEnabled = false             // sharing frames with the Mac (you switched it on)
    @ObservationIgnored var sceneActive = true
    @ObservationIgnored var lastFaceSeen = Date()
    @ObservationIgnored var captionTask: Task<Void, Never>?
    @ObservationIgnored var flashTask: Task<Void, Never>?

    /// What the face shows right now.
    var shown: Expression { isAwake ? (reaction ?? expression) : .sleeping }

    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastTouch = Date()
    @ObservationIgnored private var lastPurr = Date.distantPast
    @ObservationIgnored private var heartbeatOn = false
    @ObservationIgnored private var reactionTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    func start() {
        guard !started else { return }
        started = true
        UIApplication.shared.isIdleTimerDisabled = true   // the screen is the face: keep it on
        haptics.prepare()
        motion.onShake = { [weak self] in self?.shake() }
        motion.onFaceDown = { [weak self] in self?.sleep(because: "face down") }
        motion.onPickUp = { [weak self] in self?.wake(because: "picked up") }
        motion.start()
        setUpBrain()
        listener.onPartial = { [weak self] text in self?.heard = text }
        speaker.onFinished = { [weak self] in
            guard let self, self.expression == .thinking else { return }
            self.setExpression(.idle)
        }
        IntentBridge.attach(self)
        Task { await blinkLoop() }
        Task { await driftLoop() }
        Task { await screenCareLoop() }
    }

    // MARK: Touch

    func touched() {
        lastTouch = Date()
        if isDimmed { withAnimation(.easeOut(duration: 0.3)) { isDimmed = false } }
    }

    func tap() {
        if !isAwake { wake(because: "tap"); return }
        touched()
        if isListening { finishTalking(); return }   // after the Action button: tap to send
        if interruptSpeech() { return }               // tap while talking: stop
        haptics.play(.tap)
        note("tap")
    }

    func swipe(_ direction: SwipeDirection) {
        touched()
        guard isAwake else { return }
        switch direction {
        case .down: sleep(because: "swipe down")
        case .left: stepWidget(1)
        case .right: stepWidget(-1)
        case .up: setMode(mode == .buddy ? .inspect : .buddy)
        }
    }

    func pet() {
        touched()
        guard isAwake else { return }
        if Date().timeIntervalSince(lastPurr) > 0.9 {
            haptics.play(.purr)
            lastPurr = Date()
        }
        react(.petted, seconds: 1.4)
        note("petted")
    }

    func openSettings() { touched(); showSettings = true }

    // MARK: Wake and sleep

    func wake(because why: String) {
        touched()
        guard !isAwake else { return }
        withAnimation(.spring(duration: 0.5)) { isAwake = true }
        motion.disarmPickUp()
        haptics.play(.tap)
        note("wake: \(why)")
        link.event("wake")
        updateCamera()
    }

    func sleep(because why: String) {
        guard isAwake else { return }
        reactionTask?.cancel()
        withAnimation(.easeInOut(duration: 0.7)) {
            isAwake = false
            reaction = nil
            widget = .face
            isDimmed = false
        }
        motion.armPickUp()
        note("sleep: \(why)")
        mode = .buddy
        pointMark = nil
        cancelTalking()       // microphone off too
        link.event("sleep")
        updateCamera()   // asleep = camera off. Phase B3 adds the microphone here too.
    }

    // MARK: Moods and reactions

    func shake() {
        touched()
        guard isAwake else { return }
        haptics.play(.stop)
        react(.dizzy, seconds: 1.3)
        note("shake: cancelled")
        cancelTalking()
        link.event("shake")
        if expression == .thinking { setExpression(.idle) }
        Task {
            for i in 0..<12 {   // eyes roll round once: a dizzy look
                let angle = Double(i) * .pi / 3
                withAnimation(.linear(duration: 0.1)) {
                    look = CGPoint(x: cos(angle) * 0.6, y: sin(angle) * 0.4)
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            withAnimation(.easeOut(duration: 0.3)) { look = .zero }
        }
    }

    /// Used by the debug menu (and later by the Mac brain) to set Claudy's mood.
    func setExpression(_ new: Expression) {
        touched()
        if new.isReaction { react(new, seconds: 2); return }
        if new == .sleeping { sleep(because: "debug"); return }
        if !isAwake { wake(because: "debug") }
        withAnimation(.spring(duration: 0.5)) { expression = new }
        note("mood: \(new.label)")
        if new == .thinking { startHeartbeat() }
    }

    func react(_ e: Expression, seconds: Double) {
        reactionTask?.cancel()
        if reaction != e { withAnimation(.spring(duration: 0.35)) { reaction = e } }
        reactionTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.5)) { reaction = nil }
        }
    }

    /// While thinking, a soft heartbeat buzz keeps the wait feeling alive.
    private func startHeartbeat() {
        guard !heartbeatOn else { return }
        heartbeatOn = true
        Task {
            while expression == .thinking && isAwake {
                haptics.play(.heartbeat)
                try? await Task.sleep(for: .seconds(1.1))
            }
            heartbeatOn = false
        }
    }

    // MARK: Widgets and timer

    private func stepWidget(_ step: Int) {
        let all = Widget.allCases
        let next = all[(widget.rawValue + step + all.count) % all.count]
        withAnimation(.easeInOut(duration: 0.3)) { widget = next }
        haptics.play(.tap)
        note("widget: \(next.title)")
    }

    func startTimer(minutes: Double) {
        touched()
        timerTask?.cancel()
        timerTotal = minutes * 60
        timerEnd = Date().addingTimeInterval(timerTotal)
        haptics.play(.tap)
        timerTask = Task {
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            timerFinished()
        }
    }

    func cancelTimer() {
        timerTask?.cancel()
        timerEnd = nil
    }

    private func timerFinished() {
        timerEnd = nil
        wake(because: "timer")
        withAnimation(.easeInOut(duration: 0.3)) { widget = .timer }
        react(.happy, seconds: 2.5)
        note("timer done")
        Task {
            for _ in 0..<3 {
                haptics.play(.attention)
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }

    // MARK: Background loops

    private func blinkLoop() async {
        while true {
            try? await Task.sleep(for: .seconds(Double.random(in: 2.5...6)))
            guard isAwake, shown != .petted else { continue }
            await blinkOnce()
            if Double.random(in: 0...1) < 0.2 {   // sometimes a double blink
                try? await Task.sleep(for: .milliseconds(160))
                await blinkOnce()
            }
        }
    }

    private func blinkOnce() async {
        withAnimation(.easeIn(duration: 0.07)) { blink = 0.05 }
        try? await Task.sleep(for: .milliseconds(110))
        withAnimation(.easeOut(duration: 0.14)) { blink = 1 }
    }

    private func driftLoop() async {
        while true {
            try? await Task.sleep(for: .seconds(Double.random(in: 1.8...4.5)))
            guard isAwake, reaction == nil, !seesFace else { continue }   // following you instead
            let target = Double.random(in: 0...1) < 0.3
                ? CGPoint.zero
                : CGPoint(x: .random(in: -0.7...0.7), y: .random(in: -0.4...0.4))
            withAnimation(.easeInOut(duration: 0.9)) { look = target }
        }
    }

    /// Dims after a minute without touch, and nudges the face now and then against burn-in.
    private func screenCareLoop() async {
        var ticks = 0
        while true {
            try? await Task.sleep(for: .seconds(5))
            ticks += 1
            if isAwake, !isDimmed, widget != .light, Date().timeIntervalSince(lastTouch) > 60 {
                withAnimation(.easeInOut(duration: 1.5)) { isDimmed = true }
                note("dimmed: idle")
            }
            // Presence: with Follow me on and nobody seen for 2 minutes, go to sleep (camera off).
            if isAwake, followEnabled, cameraSide == .front, !link.status.isConnected,
               Date().timeIntervalSince(lastFaceSeen) > 120 {
                sleep(because: "nobody there for 2 minutes")
            }
            if ticks % 12 == 0 {
                withAnimation(.easeInOut(duration: 3)) {
                    burnInShift = CGSize(width: .random(in: -10...10), height: .random(in: -10...10))
                }
            }
        }
    }

    func note(_ text: String) {
        lastEvent = "\(Date().formatted(date: .omitted, time: .standard))  \(text)"
    }
}
