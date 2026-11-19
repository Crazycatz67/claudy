// AppState+Measure.swift: LiDAR distance and drag-to-measure in Inspect mode (D1, D2), and the
// "Hey Claudy" wake word (V3). The wake word listens only while its switch is on, Claudy is awake,
// the app is on screen and Claudy isn't talking; recognition happens on the phone.
import SwiftUI

extension AppState {
    func setUpMeasure() {
        camera.onDistance = { [weak self] cm in self?.distanceCM = cm }
        camera.onMeasure = { [weak self] result in self?.measured(result) }
        camera.onAspect = { [weak self] aspect in self?.pictureAspect = aspect }
    }

    // MARK: Measuring

    func setMeasuring(_ on: Bool) {
        guard mode == .inspect else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            measuring = on
            measurement = nil
            pointMark = nil
        }
        haptics.play(.tap)
        note(on ? "measure: on (LiDAR)" : "measure: off")
        updateCamera()
    }

    /// You finished dragging a box (0...1 of the picture).
    func measure(box: CGRect) {
        touched()
        guard box.width > 0.02, box.height > 0.02 else { return }
        camera.measure(box: box)
    }

    private func measured(_ result: CameraService.Measurement?) {
        guard let result else {
            showCaption("LiDAR can't see that spot. Try 25 cm to 2 m away.", quiet: true)
            return
        }
        withAnimation(.spring(duration: 0.3)) { measurement = result }
        haptics.play(.click)
        let text = String(format: "About %.0f by %.0f millimetres, %.0f centimetres away.",
                          result.widthMM, result.heightMM, result.distanceCM)
        showCaption(text, quiet: true)
        if link.status.isConnected { link.event("measure", ["width_mm": result.widthMM, "height_mm": result.heightMM,
                                                            "distance_cm": result.distanceCM]) }
    }

    // MARK: Hey Claudy

    var wakeWordEnabled: Bool { UserDefaults.standard.bool(forKey: "wakeWord") }

    /// The one place that decides whether the wake word listens.
    func updateWakeWord() {
        let wanted = wakeWordEnabled && isAwake && sceneActive && !isListening && !speaker.isSpeaking
        if wanted && !listener.isWakeListening {
            Task { [weak self] in
                guard let self, await self.listener.permitted() else { return }
                self.startWakeListening()
            }
        } else if !wanted && listener.isWakeListening {
            listener.stopWake()
            wakeListening = false
        }
    }

    private func startWakeListening() {
        guard wakeWordEnabled, isAwake, sceneActive, !isListening, !speaker.isSpeaking,
              !listener.isWakeListening else { return }
        if let problem = listener.startWake(
            onWake: { [weak self] in self?.heardWakeWord() },
            onCommand: { [weak self] text in self?.wakeCommand(text) }) {
            note("hey claudy: \(problem)")
        } else {
            wakeListening = true
            note("hey claudy: listening")
        }
    }

    private func heardWakeWord() {
        touched()
        haptics.play(.tap)
        setExpression(.listening)
        note("hey claudy: heard")
    }

    private func wakeCommand(_ text: String) {
        wakeListening = false
        if text.isEmpty {
            setExpression(.idle)
        } else {
            note("heard: \(text)")
            ask(text)
        }
        updateWakeWord()   // go back to listening for the next "Hey Claudy"
    }
}
