import AVFoundation

/// Captures the default microphone via AVAudioEngine.
final class MicCapture {
    private let engine = AVAudioEngine()
    private let resampler = AudioResampler()
    private let segmenter: Segmenter
    private(set) var running = false

    init(segmenter: Segmenter) {
        self.segmenter = segmenter
    }

    func start() throws {
        guard !running else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw NSError(domain: "Traducify", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No microphone available"])
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let samples = self.resampler.convert(buffer)
            if !samples.isEmpty { self.segmenter.push(samples) }
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }
}
