import AVFoundation
import Foundation
import SwiftUI

struct TranslationLine: Identifiable, Equatable {
    enum Speaker: String {
        case them = "THEM"   // system audio: meeting, video, call
        case me = "YOU"      // the user's mic
        case chat = "CHAT"   // typed
    }

    let id = UUID()
    let speaker: Speaker
    let original: String
    let translation: String
    let model: String
    let date = Date()
}

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case setup            // first run: needs API key and/or model
        case downloading      // pulling the whisper model
        case loading          // whisper context loading
        case running
        case failed(String)
    }

    @Published var phase: Phase = .setup
    @Published var status = "starting…"
    @Published var lines: [TranslationLine] = []
    @Published var chatResult: TranslationLine?
    @Published var downloadProgress = 0.0
    @Published var collapsed = false
    @Published var showChat = false
    @Published var config = Config.load()
    @Published var apiKeyDraft = ""
    @Published var premiumKeyDraft = ""

    var onOpenSettings: (() -> Void)?

    private var whisper: WhisperEngine?
    private var systemCapture: SystemAudioCapture?
    private var micCapture: MicCapture?
    private var transcript: Transcript?
    private let modelManager = ModelManager()
    private let sttQueue = DispatchQueue(label: "traducify.stt", qos: .userInitiated)

    private var selectedModel: WhisperModel {
        WhisperModel.all.first { $0.file == config.whisperModel } ?? WhisperModel.all[0]
    }

    private var translator: Translator {
        var attempts: [Translator.Attempt] = []
        let premiumModel = config.premiumModel.trimmingCharacters(in: .whitespaces)
        if !premiumModel.isEmpty {
            attempts.append(Translator.Attempt(
                baseURL: config.premiumBaseURL,
                apiKey: Keychain.loadKey(account: "premium-api-key"),
                model: premiumModel))
        }
        let mainKey = Keychain.loadKey()
        let chain = config.customModel.isEmpty ? config.models : [config.customModel]
        attempts += chain.map {
            Translator.Attempt(baseURL: config.baseURL, apiKey: mainKey, model: $0)
        }
        return Translator(attempts: attempts)
    }

    // MARK: - lifecycle

    func bootstrap() {
        apiKeyDraft = Keychain.loadKey()
        premiumKeyDraft = Keychain.loadKey(account: "premium-api-key")
        if apiKeyDraft.isEmpty || !ModelManager.isDownloaded(selectedModel) {
            phase = .setup
            status = "welcome - one-time setup"
        } else {
            startPipeline()
        }
    }

    func completeSetup() {
        Keychain.saveKey(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        config.onboarded = true
        config.save()
        if ModelManager.isDownloaded(selectedModel) {
            startPipeline()
        } else {
            downloadModel()
        }
    }

    private func downloadModel() {
        phase = .downloading
        status = "downloading \(selectedModel.label)…"
        modelManager.download(selectedModel) { [weak self] progress in
            Task { @MainActor in self?.downloadProgress = progress }
        } completion: { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success: self?.startPipeline()
                case .failure(let error):
                    self?.phase = .failed("model download failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func startPipeline() {
        phase = .loading
        status = "loading whisper model…"
        let modelPath = ModelManager.localURL(for: selectedModel).path
        let cfg = config

        Task { [weak self] in
            do {
                let engine = try await Task.detached { try WhisperEngine(modelPath: modelPath) }.value
                self?.whisper = engine
                self?.startCaptures(cfg)
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func startCaptures(_ cfg: Config) {
        if transcript == nil, cfg.saveTranscripts { transcript = Transcript() }

        let systemSegmenter = Segmenter(channel: .system, config: cfg)
        systemSegmenter.onSegment = { [weak self] channel, audio in
            self?.handleSegment(channel: channel, audio: audio)
        }
        let capture = SystemAudioCapture(segmenter: systemSegmenter)
        capture.onError = { [weak self] message in
            Task { @MainActor in self?.status = message }
        }
        systemCapture = capture

        Task {
            do {
                try await capture.start()
                phase = .running
                status = "listening to system audio"
                if config.micEnabled { startMic() }
            } catch {
                phase = .failed("Screen & System Audio Recording permission needed. " +
                                "Grant it in System Settings > Privacy & Security > Screen & System Audio Recording, then relaunch Traducify.")
            }
        }
    }

    func startMic() {
        guard micCapture == nil || micCapture?.running == false else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.status = "microphone permission denied"
                    self.config.micEnabled = false
                    return
                }
                let segmenter = Segmenter(channel: .mic, config: self.config)
                segmenter.onSegment = { [weak self] channel, audio in
                    self?.handleSegment(channel: channel, audio: audio)
                }
                let mic = MicCapture(segmenter: segmenter)
                do {
                    try mic.start()
                    self.micCapture = mic
                    self.status = "listening to system audio + mic"
                } catch {
                    self.status = "mic failed: \(error.localizedDescription)"
                    self.config.micEnabled = false
                }
            }
        }
    }

    func stopMic() {
        micCapture?.stop()
        micCapture = nil
        if phase == .running { status = "listening to system audio" }
    }

    func toggleMic() {
        config.micEnabled.toggle()
        config.save()
        if config.micEnabled { startMic() } else { stopMic() }
    }

    /// Settings changed: persist, and reload whatever the change touches.
    func applySettings(reloadModel: Bool) {
        Keychain.saveKey(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        Keychain.saveKey(premiumKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                         account: "premium-api-key")
        config.save()
        if reloadModel {
            shutdown()
            whisper = nil
            bootstrap()
        }
    }

    nonisolated func shutdown() {
        Task { @MainActor in
            self.systemCapture?.stop()
            self.systemCapture = nil
            self.stopMic()
        }
    }

    // MARK: - pipeline

    nonisolated private func handleSegment(channel: Segmenter.Channel, audio: [Float]) {
        sttQueue.async { [weak self] in
            guard let self else { return }
            let (whisper, cfg) = DispatchQueue.main.sync { (self.whisper, self.config) }
            guard let whisper else { return }

            let hint = channel == .system ? cfg.theirLanguage : cfg.myLanguage
            let text = whisper.transcribe(audio, language: hint)
            guard !text.isEmpty else { return }

            let from = hint.isEmpty ? whisper.detectedLanguage() : hint
            let to = channel == .system ? cfg.myLanguage : cfg.theirLanguage
            guard from != to else { return }

            Task { @MainActor in
                self.translateAndPublish(
                    speaker: channel == .system ? .them : .me,
                    text: text, from: from, to: to)
            }
        }
    }

    private func translateAndPublish(speaker: TranslationLine.Speaker, text: String,
                                     from: String, to: String) {
        let translator = self.translator
        Task {
            do {
                let (translation, model) = try await translator.translate(text, from: from, to: to)
                let line = TranslationLine(speaker: speaker, original: text,
                                           translation: translation, model: model)
                await MainActor.run {
                    self.lines.append(line)
                    if self.lines.count > 100 { self.lines.removeFirst(self.lines.count - 100) }
                }
                self.transcript?.log(speaker: speaker.rawValue, original: text, translation: translation)
            } catch {
                await MainActor.run { self.status = "translation failed: \(error.localizedDescription)" }
            }
        }
    }

    /// Chat box: typed in the user's language, shown big in theirs.
    func sendChat(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let translator = self.translator
        let (from, to) = (config.myLanguage, config.theirLanguage)
        let target = to.isEmpty ? "es" : to  // auto-detect has no target; fall back
        Task {
            do {
                let (translation, model) = try await translator.translate(trimmed, from: from, to: target)
                let line = TranslationLine(speaker: .chat, original: trimmed,
                                           translation: translation, model: model)
                await MainActor.run { self.chatResult = line }
                self.transcript?.log(speaker: "CHAT", original: trimmed, translation: translation)
            } catch {
                await MainActor.run { self.status = "translation failed: \(error.localizedDescription)" }
            }
        }
    }
}
