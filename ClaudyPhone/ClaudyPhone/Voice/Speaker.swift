// Speaker.swift: text to speech on the phone (AVSpeechSynthesizer), with a chosen voice and speed.
// Can be stopped mid-sentence (tap or shake).
import AVFoundation

@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    var onFinished: () -> Void = {}
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    /// Voices for the picker in settings: the user's language first, best quality first.
    static func voices() -> [AVSpeechSynthesisVoice] {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }

    func speak(_ text: String) {
        let defaults = UserDefaults.standard
        let utterance = AVSpeechUtterance(string: text)
        if let id = defaults.string(forKey: "voiceID"), let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        } else {
            utterance.voice = Self.voices().first
        }
        let speed = defaults.object(forKey: "voiceSpeed") as? Double ?? 0.5
        utterance.rate = AVSpeechUtteranceMinimumSpeechRate
            + Float(speed) * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate) * 0.6
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onFinished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onFinished() }
    }
}
