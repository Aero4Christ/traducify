import Foundation
import whisper

/// Local transcription via whisper.cpp (Metal). The context loads once and is
/// reused for every segment; calls are serialized by the pipeline.
final class WhisperEngine: @unchecked Sendable {  // used serially from sttQueue
    private let ctx: OpaquePointer

    /// Whisper hallucinates these on silence/noise; never forward them.
    private static let hallucinationPattern = try! NSRegularExpression(
        pattern: #"^[\s\[\(\.\-]*(\[.*\]|\(.*\)|música|music|applause|aplausos|"# +
                 #"subtítulos.*|subtitles.*|gracias por ver.*|thank you for watching.*)?[\s\.\-]*$"#,
        options: [.caseInsensitive])

    init(modelPath: String) throws {
        var params = whisper_context_default_params()
        params.use_gpu = true
        guard let ctx = whisper_init_from_file_with_params(modelPath, params) else {
            throw NSError(domain: "Traducify", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load whisper model"])
        }
        self.ctx = ctx
    }

    deinit { whisper_free(ctx) }

    /// Transcribe 16 kHz mono samples. `language` is a whisper code, "" = auto-detect.
    /// `prompt` is recent same-language text fed as initial_prompt for continuity.
    func transcribe(_ samples: [Float], language: String, prompt: String = "") -> String {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount - 2))
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.no_context = true
        params.suppress_blank = true
        params.translate = false

        // Each VAD chunk is one utterance: keep it a single segment so whisper
        // does not invent a phantom trailing segment on the closing silence.
        params.single_segment = true
        // Suppress non-speech tokens ("[music]", "(applause)") at the source.
        params.suppress_nst = true
        // Anti-hallucination gates, pinned to the library defaults so they are
        // visible and tunable and survive any upstream default change. A greedy
        // decode that trips these retries at a higher temperature; if it still
        // fails, the segment is dropped instead of emitted as garbage.
        params.temperature = 0.0
        params.temperature_inc = 0.2
        params.entropy_thold = 2.4    // catches repetition loops
        params.logprob_thold = -1.0   // drops low-confidence decodes
        params.no_speech_thold = 0.6  // drops non-speech / silence

        let run: () -> Int32 = {
            samples.withUnsafeBufferPointer { buf in
                whisper_full(self.ctx, params, buf.baseAddress, Int32(buf.count))
            }
        }
        // language and initial_prompt are C strings that must outlive the
        // whisper_full call; bind both (nil when empty) before running.
        func withOptionalCString<R>(_ s: String, _ body: (UnsafePointer<CChar>?) -> R) -> R {
            if s.isEmpty { return body(nil) }
            return s.withCString { body($0) }
        }
        let status = withOptionalCString(language) { lang in
            params.language = lang
            return withOptionalCString(prompt) { pr in
                params.initial_prompt = pr
                return run()
            }
        }
        guard status == 0 else { return "" }

        var text = ""
        for i in 0..<whisper_full_n_segments(ctx) {
            if let seg = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: seg)
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let range = NSRange(text.startIndex..., in: text)
        if WhisperEngine.hallucinationPattern.firstMatch(in: text, range: range) != nil {
            return ""
        }
        return text
    }

    /// Language whisper detected for the last transcription (for auto-detect mode).
    func detectedLanguage() -> String {
        let id = whisper_full_lang_id(ctx)
        guard id >= 0, let cstr = whisper_lang_str(id) else { return "" }
        return String(cString: cstr)
    }
}
