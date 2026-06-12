import Foundation

/// OpenAI-compatible chat-completions client. Walks a list of attempts, each
/// with its own endpoint, key, and model: the premium slot first (if set),
/// then the fallback chain on the main provider.
struct Translator {
    struct Attempt {
        let baseURL: String
        let apiKey: String
        let model: String
    }

    let attempts: [Attempt]

    struct Failure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Forgiving endpoint builder: tolerates trailing slashes, a pasted
    /// /chat/completions suffix, and a bare host with no /v1 path.
    static func endpoint(for baseURL: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if base.lowercased().hasSuffix("/chat/completions") {
            base.removeLast("/chat/completions".count)
        }
        guard !base.isEmpty, let probe = URL(string: base), probe.host != nil else { return nil }
        if probe.path.isEmpty || probe.path == "/" { base += "/v1" }
        return URL(string: base + "/chat/completions")
    }

    /// Returns (translation, model that produced it).
    func translate(_ text: String, from: String, to: String) async throws -> (String, String) {
        var failures: [String] = []
        for attempt in attempts where !attempt.model.isEmpty {
            do {
                let result = try await request(text, from: from, to: to, attempt: attempt)
                if !result.isEmpty { return (result, attempt.model) }
            } catch {
                failures.append("\(attempt.model): \(error.localizedDescription)")
            }
        }
        switch failures.count {
        case 0: throw Failure(message: "no models configured")
        case 1: throw Failure(message: failures[0])
        default:
            // the first failure is usually the actionable one (key/credits);
            // the last is just where the chain ran out
            throw Failure(message: "all \(failures.count) models failed. First: \(failures.first!)")
        }
    }

    private func request(_ text: String, from: String, to: String, attempt: Attempt) async throws -> String {
        let source = from.isEmpty ? "its original language" : Language.named(from)
        let target = Language.named(to)
        let system = """
        You are a professional simultaneous interpreter. Translate the user's message \
        from \(source) to \(target). Output ONLY the translation, nothing else. \
        Preserve tone, register, and meaning. If the message is already in \(target), \
        output it unchanged.
        """

        guard let endpoint = Translator.endpoint(for: attempt.baseURL) else {
            throw Failure(message: "invalid base URL: \(attempt.baseURL)")
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(attempt.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("Traducify", forHTTPHeaderField: "X-Title")
        req.setValue("https://github.com/Aero4Christ/traducify", forHTTPHeaderField: "HTTP-Referer")

        let body: [String: Any] = [
            "model": attempt.model,
            "max_tokens": 1024,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": text],
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw Failure(message: "no response") }
        guard http.statusCode == 200 else {
            // surface the provider's own explanation, not a JSON blob
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let message = err["message"] as? String {
                throw Failure(message: "HTTP \(http.statusCode): \(message)")
            }
            let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw Failure(message: "HTTP \(http.statusCode) \(snippet)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw Failure(message: "malformed response")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
