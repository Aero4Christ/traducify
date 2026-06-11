import Foundation

/// OpenAI-compatible chat-completions client. Defaults to OpenRouter; the
/// Advanced settings point it at any provider that speaks the same protocol.
struct Translator {
    let baseURL: String
    let apiKey: String
    let models: [String]

    struct Failure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Returns (translation, model that produced it). Walks the fallback chain.
    func translate(_ text: String, from: String, to: String) async throws -> (String, String) {
        var lastError = "no models configured"
        for model in models where !model.isEmpty {
            do {
                let result = try await request(text, from: from, to: to, model: model)
                if !result.isEmpty { return (result, model) }
            } catch {
                lastError = "\(model): \(error.localizedDescription)"
            }
        }
        throw Failure(message: lastError)
    }

    private func request(_ text: String, from: String, to: String, model: String) async throws -> String {
        let source = from.isEmpty ? "its original language" : Language.named(from)
        let target = Language.named(to)
        let system = """
        You are a professional simultaneous interpreter. Translate the user's message \
        from \(source) to \(target). Output ONLY the translation, nothing else. \
        Preserve tone, register, and meaning. If the message is already in \(target), \
        output it unchanged.
        """

        var req = URLRequest(url: URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                                      + "/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("Traducify", forHTTPHeaderField: "X-Title")
        req.setValue("https://github.com/Aero4Christ/traducify", forHTTPHeaderField: "HTTP-Referer")

        let body: [String: Any] = [
            "model": model,
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
