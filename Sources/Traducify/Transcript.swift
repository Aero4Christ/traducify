import Foundation

/// Per-session bilingual transcript in ~/Documents/Traducify.
final class Transcript {
    private let url: URL
    private let queue = DispatchQueue(label: "traducify.transcript")
    private var started = false

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Traducify")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Transcript.stamp("yyyy-MM-dd-HHmm")
        url = dir.appendingPathComponent("session-\(stamp).md")
    }

    func log(speaker: String, original: String, translation: String) {
        queue.async { [self] in
            if !started {
                started = true
                let header = "# Traducify session - \(Transcript.stamp("yyyy-MM-dd HH:mm"))\n\n"
                try? header.write(to: url, atomically: true, encoding: .utf8)
            }
            let line = "**\(speaker)** [\(Transcript.stamp("HH:mm:ss"))]: \(original)\n> \(translation)\n\n"
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            }
        }
    }

    private static func stamp(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: Date())
    }
}
