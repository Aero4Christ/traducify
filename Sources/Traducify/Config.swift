import Foundation

struct Language: Identifiable, Hashable {
    let code: String   // whisper language code, "" = auto-detect
    let name: String
    var id: String { code }

    static let auto = Language(code: "", name: "Auto-detect")
    static let all: [Language] = [
        Language(code: "en", name: "English"),
        Language(code: "es", name: "Spanish"),
        Language(code: "zh", name: "Chinese"),
        Language(code: "hi", name: "Hindi"),
        Language(code: "ar", name: "Arabic"),
        Language(code: "pt", name: "Portuguese"),
        Language(code: "fr", name: "French"),
        Language(code: "de", name: "German"),
        Language(code: "ja", name: "Japanese"),
        Language(code: "ko", name: "Korean"),
        Language(code: "ru", name: "Russian"),
        Language(code: "it", name: "Italian"),
        Language(code: "nl", name: "Dutch"),
        Language(code: "pl", name: "Polish"),
        Language(code: "tr", name: "Turkish"),
        Language(code: "vi", name: "Vietnamese"),
        Language(code: "th", name: "Thai"),
        Language(code: "id", name: "Indonesian"),
        Language(code: "tl", name: "Tagalog"),
        Language(code: "uk", name: "Ukrainian"),
        Language(code: "he", name: "Hebrew"),
        Language(code: "el", name: "Greek"),
        Language(code: "sv", name: "Swedish"),
        Language(code: "ro", name: "Romanian"),
    ]

    static func named(_ code: String) -> String {
        if code.isEmpty { return "Auto-detect" }
        return all.first { $0.code == code }?.name ?? code
    }
}

struct WhisperModel: Identifiable, Hashable {
    let file: String
    let label: String
    let sizeMB: Int
    var id: String { file }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(file)")!
    }

    static let all: [WhisperModel] = [
        WhisperModel(file: "ggml-large-v3-turbo.bin", label: "Best (large-v3-turbo, 1.5 GB)", sizeMB: 1536),
        WhisperModel(file: "ggml-small.bin", label: "Light (small, 466 MB)", sizeMB: 466),
    ]
}

struct Config: Codable {
    // languages
    var theirLanguage = "es"     // what the speakers/meeting audio speaks ("" = auto)
    var myLanguage = "en"        // what the user reads and types in

    // pipeline
    var micEnabled = false       // translate my own speech the other way (conversation mode)
    var whisperModel = "ggml-large-v3-turbo.bin"

    // provider (OpenAI-compatible)
    var baseURL = "https://openrouter.ai/api/v1"
    var models = [
        "anthropic/claude-haiku-4.5",
        "google/gemini-2.5-flash-lite",
        "meta-llama/llama-3.3-70b-instruct:free",
        "google/gemma-3-27b-it:free",
    ]
    var customModel = ""         // Advanced: overrides the chain when non-empty

    // VAD
    var thresholdDb: Float = -38.0
    var silenceMs = 700
    var minSpeechMs = 400
    var maxSegmentS = 12

    // misc
    var saveTranscripts = true
    var onboarded = false

    static var supportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Traducify")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var modelsDir: URL {
        let dir = supportDir.appendingPathComponent("models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var fileURL: URL { supportDir.appendingPathComponent("config.json") }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return cfg
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? (try? encoder.encode(self))?.write(to: Config.fileURL)
    }
}
