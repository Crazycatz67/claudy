// Listener.swift: speech to text, on the phone only (on-device recognition is required, so no audio
// ever leaves the phone). The microphone runs only between start() and stop(): you hold the face,
// or press the Action button.
import AVFoundation
import Speech

@MainActor
final class Listener {
    /// Called with the words heard so far (for the live caption).
    var onPartial: (String) -> Void = { _ in }

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private(set) var isListening = false

    // "Hey Claudy" mode: listen continuously (on the phone only) for the wake phrase, then the request.
    private(set) var isWakeListening = false
    private var onWake: () -> Void = {}
    private var onCommand: (String) -> Void = { _ in }
    private var woke = false
    private var lastChange = Date()
    private var wakeStarted = Date()
    private var wakeTimer: Task<Void, Never>?
    static let wakePhrases = ["hey claudy", "hey claudie", "hey cloudy", "hey clody", "hey claude e", "hey claude"]

    /// Asks iOS for speech and microphone permission (first time only).
    func permitted() async -> Bool {
        let speech = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// Starts the microphone. Returns an error message if listening can't start.
    func start() -> String? {
        guard !isListening else { return nil }
        let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else { return "Speech recognition isn't available right now." }
        guard recognizer.supportsOnDeviceRecognition else {
            return "This language can't be recognised on the phone, so I won't listen."
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return "The microphone couldn't start."
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true      // privacy: never send audio anywhere
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            return "The microphone couldn't start."
        }
        latest = ""
        self.recognizer = recognizer
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in
                guard let self else { return }
                if text != self.latest { self.lastChange = Date() }
                self.latest = text
                if self.isWakeListening { self.checkWake(text) } else { self.onPartial(text) }
            }
        }
        isListening = true
        return nil
    }

    /// Stops the microphone (the orange dot goes out) and returns what was heard.
    func stop() async -> String {
        guard isListening else { return "" }
        isListening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        try? await Task.sleep(for: .milliseconds(450))   // let the last words finish
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return latest.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stops at once and throws the words away (shake = never mind).
    func cancel() {
        guard isListening else { return }
        isListening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Hey Claudy

    /// Starts listening for "Hey Claudy". Returns an error message if it can't start.
    func startWake(onWake: @escaping () -> Void, onCommand: @escaping (String) -> Void) -> String? {
        guard !isListening else { return nil }
        self.onWake = onWake
        self.onCommand = onCommand
        if let problem = start() { return problem }
        isWakeListening = true
        woke = false
        wakeStarted = Date()
        lastChange = Date()
        wakeTimer?.cancel()
        wakeTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                self?.wakeTick()
            }
        }
        return nil
    }

    func stopWake() {
        wakeTimer?.cancel()
        wakeTimer = nil
        guard isWakeListening else { return }
        isWakeListening = false
        cancel()
    }

    private func checkWake(_ text: String) {
        guard !woke, Self.command(after: text) != nil else { return }
        woke = true
        lastChange = Date()
        onWake()
    }

    /// The words after the wake phrase, or nil if the phrase wasn't said.
    private static func command(after text: String) -> String? {
        let lower = text.lowercased()
        for phrase in wakePhrases {
            if let range = lower.range(of: phrase, options: .backwards) {
                return String(text[range.upperBound...])
                    .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
            }
        }
        return nil
    }

    private func wakeTick() {
        guard isWakeListening else { return }
        let quiet = Date().timeIntervalSince(lastChange)
        if woke {
            let command = Self.command(after: latest) ?? ""
            // Done when you pause for 1.5 s after speaking, or 6 s pass with nothing said.
            if (!command.isEmpty && quiet > 1.5) || quiet > 6 {
                stopWake()
                onCommand(command)
            }
        } else if Date().timeIntervalSince(wakeStarted) > 50 {
            // Start fresh now and then, so the transcript stays short.
            let wake = onWake, command = onCommand
            stopWake()
            _ = startWake(onWake: wake, onCommand: command)
        }
    }
}
