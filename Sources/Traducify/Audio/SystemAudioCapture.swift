import AVFoundation
import ScreenCaptureKit

/// Captures everything playing through the speakers via ScreenCaptureKit.
/// Needs the Screen & System Audio Recording permission; no loopback driver.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let resampler = AudioResampler()
    private let segmenter: Segmenter
    var onError: ((String) -> Void)?

    init(segmenter: Segmenter) {
        self.segmenter = segmenter
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw NSError(domain: "Traducify", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No display found for audio capture"])
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        // video is mandatory for SCStream; keep it as cheap as possible
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue:
            DispatchQueue(label: "traducify.system-audio"))
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        let stream = self.stream
        self.stream = nil
        Task { try? await stream?.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              let pcm = sampleBuffer.toPCMBuffer() else { return }
        let samples = resampler.convert(pcm)
        if !samples.isEmpty { segmenter.push(samples) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?("system audio stopped: \(error.localizedDescription)")
    }
}

extension CMSampleBuffer {
    /// Wrap a ScreenCaptureKit audio sample buffer as an AVAudioPCMBuffer (no copy beyond AVFoundation's own).
    func toPCMBuffer() -> AVAudioPCMBuffer? {
        guard let desc = CMSampleBufferGetFormatDescription(self),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) else { return nil }
        guard let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard frames > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
        return status == noErr ? pcm : nil
    }
}
