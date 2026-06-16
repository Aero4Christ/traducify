import Foundation
import whisper

/// Silero voice-activity detection via whisper.cpp. Loaded once and used
/// serially on the STT queue to confirm a candidate segment actually contains
/// speech before it is transcribed, filtering the energy segmenter's false
/// triggers (music, noise, room tone). Optional: if the model is missing the
/// pipeline falls back to energy-only segmentation.
final class VadEngine: @unchecked Sendable {  // used serially from sttQueue
    private let vctx: OpaquePointer
    private let params: whisper_vad_params

    init(modelPath: String) throws {
        var cparams = whisper_vad_default_context_params()
        cparams.use_gpu = false  // tiny model; CPU is instant and leaves the GPU to whisper
        guard let vctx = whisper_vad_init_from_file_with_params(modelPath, cparams) else {
            throw NSError(domain: "Traducify", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load VAD model"])
        }
        self.vctx = vctx
        self.params = whisper_vad_default_params()
    }

    deinit { whisper_vad_free(vctx) }

    /// True if the buffer holds at least one speech segment. Fails open: if
    /// detection errors, keep the segment rather than silently dropping speech.
    func isSpeech(_ samples: [Float]) -> Bool {
        let segs = samples.withUnsafeBufferPointer { buf in
            whisper_vad_segments_from_samples(vctx, params, buf.baseAddress, Int32(buf.count))
        }
        guard let segs else { return true }
        let n = whisper_vad_segments_n_segments(segs)
        whisper_vad_free_segments(segs)
        return n > 0
    }
}
