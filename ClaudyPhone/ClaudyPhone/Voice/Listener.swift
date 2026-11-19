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
                self?.latest = text
                self?.onPartial(text)
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
}
