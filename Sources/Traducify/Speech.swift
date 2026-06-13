import AVFoundation

/// Reads a translation aloud so the other person can hear it in their language.
/// Uses the macOS voices already installed; no network, no cost.
@MainActor
final class Speech {
    static let shared = Speech()
    private let synth = AVSpeechSynthesizer()

    /// `langCode` is a 2-letter whisper code ("es", "en"); AVSpeech matches a
    /// regional voice if one exists, otherwise the system default.
    func speak(_ text: String, langCode: String) {
        guard !text.isEmpty else { return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        if !langCode.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(language: bcp47(langCode))
                ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(langCode + "-") }
        }
        synth.speak(utterance)
    }

    /// Map a bare language code to a common regional default AVSpeech accepts.
    private func bcp47(_ code: String) -> String {
        let defaults = [
            "en": "en-US", "es": "es-MX", "pt": "pt-BR", "zh": "zh-CN",
            "fr": "fr-FR", "de": "de-DE", "it": "it-IT", "ja": "ja-JP",
            "ko": "ko-KR", "ru": "ru-RU", "ar": "ar-SA", "hi": "hi-IN",
            "nl": "nl-NL", "pl": "pl-PL", "tr": "tr-TR", "vi": "vi-VN",
            "th": "th-TH", "id": "id-ID", "uk": "uk-UA", "he": "he-IL",
            "el": "el-GR", "sv": "sv-SE", "ro": "ro-RO",
        ]
        return defaults[code] ?? code
    }
}
