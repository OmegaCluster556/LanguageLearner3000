import AVFoundation
import Observation

/// Text-to-speech using Apple's built-in Russian (ru-RU) and Ukrainian (uk-UA) voices.
@MainActor
@Observable
final class SpeechService {
    static let shared = SpeechService()

    /// Set when the device has no voice installed for a language (shown as an alert).
    var missingVoice: Language?
    private(set) var isSpeaking = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let delegate = Delegate()

    private static var voiceCache: [Language: AVSpeechSynthesisVoice?] = [:]

    private init() {
        synthesizer.delegate = delegate
        delegate.onChange = { [weak self] speaking in
            Task { @MainActor in self?.isSpeaking = speaking }
        }
    }

    /// Starts the audio session and loads voices in the background so the
    /// first tap on a word doesn't stall the UI. Call once at launch.
    nonisolated static func warmUp() {
        Task.detached(priority: .utility) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? session.setActive(true)
            _ = AVSpeechSynthesisVoice.speechVoices()
        }
    }

    static func bestVoice(for language: Language) -> AVSpeechSynthesisVoice? {
        if let cached = voiceCache[language] { return cached }
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language.speechCode }
        let voice = candidates.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: language.speechCode)
        voiceCache[language] = voice
        return voice
    }

    static func hasVoice(for language: Language) -> Bool { bestVoice(for: language) != nil }

    func speak(_ text: String, language: Language, slow: Bool = false) {
        guard let voice = Self.bestVoice(for: language) else {
            missingVoice = language
            return
        }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        let stored = UserDefaults.standard.object(forKey: "speechRate") as? Double ?? 0.45
        let base = Float(stored) * (AVSpeechUtteranceDefaultSpeechRate / 0.5)
        utterance.rate = slow ? max(AVSpeechUtteranceMinimumSpeechRate, base * 0.6) : base
        utterance.preUtteranceDelay = 0.05
        synthesizer.speak(utterance)
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }

    private final class Delegate: NSObject, AVSpeechSynthesizerDelegate {
        var onChange: ((Bool) -> Void)?
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) { onChange?(true) }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { onChange?(false) }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { onChange?(false) }
    }
}
