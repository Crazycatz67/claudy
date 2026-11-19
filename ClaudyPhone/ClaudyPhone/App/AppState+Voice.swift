// AppState+Voice.swift: talking with Claudy. Hold the face (or press the Action button) to talk,
// let go to send; answers are spoken by the phone with captions; tap or shake interrupts.
// The microphone runs only while you are holding the face or after you pressed the button.
import SwiftUI

extension AppState {
    /// Hold-to-talk started (or the Action button / Shortcut was used).
    func startTalking(fromButton: Bool = false) {
        wake(because: fromButton ? "Action button" : "hold to talk")
        speaker.stop()
        guard !isListening else { return }
        listener.stopWake()          // hold-to-talk takes over the microphone
        wakeListening = false
        Task {
            guard await listener.permitted() else {
                say("I need microphone and speech permission to hear you. You can allow it in the Settings app.", quiet: true)
                return
            }
            if let problem = listener.start() {
                say(problem, quiet: true)
                return
            }
            isListening = true
            heard = ""
            haptics.play(.tap)
            setExpression(.listening)
            note("listening")
            if fromButton { autoStopListening() }
        }
    }

    /// Let go: stop the microphone and send what was heard to the Mac.
    func finishTalking() {
        guard isListening else { return }
        isListening = false
        Task {
            let text = await listener.stop()
            heard = ""
            defer { updateWakeWord() }
            guard !text.isEmpty else {
                setExpression(.idle)
                showCaption("I didn't catch that.", quiet: true)
                return
            }
            note("heard: \(text)")
            ask(text)
        }
    }

    /// Shake or sleep: stop listening and throw the words away.
    func cancelTalking() {
        if isListening {
            listener.cancel()
            isListening = false
            heard = ""
        }
        speaker.stop()
    }

    /// Send a question to the Mac brain.
    func ask(_ text: String, point: CGPoint? = nil) {
        guard link.status.isConnected else {
            react(.concerned, seconds: 2)
            setExpression(.idle)
            say("My brain is offline, so I can't answer that yet.", quiet: false)
            return
        }
        var json: [String: Any] = ["type": "ask", "text": text]
        if let point { json["point"] = ["x": point.x, "y": point.y] }
        link.send(json)
        setExpression(.thinking)
        showCaption("“\(text)”", quiet: false)
    }

    /// Claudy speaks (unless quiet), always with a caption.
    func say(_ text: String, quiet: Bool) {
        let quietMode = UserDefaults.standard.bool(forKey: "quietMode")
        showCaption(text, quiet: quiet || quietMode)
        if expression == .thinking { setExpression(.idle) }
        guard !quiet, !quietMode, !text.isEmpty else { return }
        listener.stopWake()          // don't listen to ourselves
        wakeListening = false
        speaker.speak(text)
    }

    /// Tap while Claudy talks: stop at once. Returns true if it was talking.
    func interruptSpeech() -> Bool {
        guard speaker.isSpeaking else { return false }
        speaker.stop()
        haptics.play(.stop)
        note("interrupted")
        return true
    }

    /// Shortcuts: take a full-detail photo and send it to the Mac.
    func takePhotoForMac() {
        wake(because: "photo shortcut")
        guard cameraOn else {
            say("Turn on Inspect mode or camera sharing first, then I can take a photo.", quiet: true)
            return
        }
        flashPhotoEyes()
        camera.capturePhoto(id: "shortcut-\(Int(Date().timeIntervalSince1970))")
    }

    /// Shortcuts: tell the brain what you are doing.
    func setTask(_ text: String) {
        link.event("task", text)
        showCaption("Task: \(text)", quiet: true)
        note("task: \(text)")
    }

    /// After the Action button there is no finger to lift, so stop after 8 seconds.
    private func autoStopListening() {
        Task {
            try? await Task.sleep(for: .seconds(8))
            if isListening { finishTalking() }
        }
    }
}
