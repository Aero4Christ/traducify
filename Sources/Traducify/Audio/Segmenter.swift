import Foundation

/// Energy-based voice activity detection over 16 kHz mono Float32 frames.
/// Collects speech into complete segments and emits them via `onSegment`.
final class Segmenter {
    static let sampleRate = 16000
    static let frameMs = 30
    static let frameSamples = sampleRate * frameMs / 1000  // 480

    let channel: Channel
    var onSegment: ((Channel, [Float]) -> Void)?

    private let thresholdDb: Float
    private let silenceFrames: Int
    private let minSpeechFrames: Int
    private let maxSegmentFrames: Int
    private let preRollFrames = 10  // ~300 ms kept before speech onset

    private var noiseFloorDb: Float = -55.0  // adaptive, updated while idle
    private var pending: [Float] = []        // partial frame carry-over
    private var preRoll: [[Float]] = []
    private var segment: [[Float]] = []
    private var inSpeech = false
    private var silentRun = 0
    private let queue: DispatchQueue

    enum Channel: String {
        case system  // speakers: meeting, video, movie, call
        case mic     // the user's own voice
    }

    init(channel: Channel, config: Config) {
        self.channel = channel
        self.thresholdDb = config.thresholdDb
        self.silenceFrames = max(1, config.silenceMs / Segmenter.frameMs)
        self.minSpeechFrames = max(1, config.minSpeechMs / Segmenter.frameMs)
        self.maxSegmentFrames = config.maxSegmentS * 1000 / Segmenter.frameMs
        self.queue = DispatchQueue(label: "traducify.segmenter.\(channel.rawValue)")
    }

    /// Feed any number of 16 kHz mono samples; thread-safe.
    func push(_ samples: [Float]) {
        queue.async { [self] in
            pending.append(contentsOf: samples)
            while pending.count >= Segmenter.frameSamples {
                let frame = Array(pending.prefix(Segmenter.frameSamples))
                pending.removeFirst(Segmenter.frameSamples)
                process(frame)
            }
        }
    }

    private func process(_ frame: [Float]) {
        let db = Segmenter.dbfs(frame)
        let gate = max(thresholdDb, noiseFloorDb + 8.0)

        if !inSpeech {
            // slow EMA of the noise floor while idle
            noiseFloorDb = 0.98 * noiseFloorDb + 0.02 * db
            preRoll.append(frame)
            if preRoll.count > preRollFrames { preRoll.removeFirst() }
            if db > gate {
                inSpeech = true
                segment = preRoll
                segment.append(frame)
                silentRun = 0
            }
        } else {
            segment.append(frame)
            silentRun = db <= gate ? silentRun + 1 : 0
            let done = silentRun >= silenceFrames
            let tooLong = segment.count >= maxSegmentFrames
            if done || tooLong {
                let speechFrames = segment.count - (done ? silentRun : 0)
                if speechFrames >= minSpeechFrames {
                    let audio = segment.flatMap { $0 }
                    onSegment?(channel, audio)
                }
                preRoll = []
                segment = []
                inSpeech = false
                silentRun = 0
            }
        }
    }

    private static func dbfs(_ frame: [Float]) -> Float {
        var sum: Float = 0
        for s in frame { sum += s * s }
        let rms = (sum / Float(frame.count)).squareRoot()
        return 20.0 * log10(rms + 1e-10)
    }
}
