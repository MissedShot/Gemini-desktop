import Foundation

enum GeminiAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case emptyResponse
    case apiError(statusCode: Int, body: String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to build Gemini request URL."
        case .invalidResponse:
            return "Gemini returned invalid HTTP response."
        case .emptyResponse:
            return "Gemini returned an empty response."
        case .apiError(let statusCode, let body):
            let parsed = Self.parseAPIErrorMessage(from: body) ?? body
            return "Gemini API error (\(statusCode)): \(parsed)"
        case .requestFailed(let message):
            return message
        }
    }

    private static func parseAPIErrorMessage(from rawBody: String) -> String? {
        guard let data = rawBody.data(using: .utf8) else { return nil }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            return nil
        }
        return message
    }
}

struct GeminiGenerateRequest: Encodable {
    struct Content: Encodable {
        struct Part: Encodable {
            let text: String
        }

        let role: String
        let parts: [Part]
    }

    struct SystemInstruction: Encodable {
        let parts: [Content.Part]
    }

    struct SafetySetting: Encodable {
        let category: String
        let threshold: String
    }

    let contents: [Content]
    let systemInstruction: SystemInstruction?
    let safetySettings: [SafetySetting]?
}

struct GeminiGenerateResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
            }

            let parts: [Part]
        }

        let content: Content
        let finishReason: String?
    }

    struct PromptFeedback: Decodable {
        let blockReason: String?
    }

    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
}

struct GeminiListModelsResponse: Decodable {
    struct Model: Decodable {
        let name: String
        let supportedGenerationMethods: [String]?
    }

    let models: [Model]?
}

actor GeminiAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generateReply(
        messages: [ChatMessage],
        apiKey: String,
        model: String,
        systemPrompt: String? = nil,
        safetyPreset: GeminiSafetyPreset = .default
    ) async throws -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw GeminiAPIError.requestFailed("Model cannot be empty.")
        }

        let requestBody = makeGenerateBody(
            messages: messages,
            systemPrompt: systemPrompt,
            safetyPreset: safetyPreset
        )
        let request = try makeGenerateRequest(
            apiKey: apiKey,
            model: trimmedModel,
            body: requestBody,
            streaming: false
        )

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GeminiAPIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let rawBody = String(data: data, encoding: .utf8) ?? "<empty>"
            throw GeminiAPIError.apiError(statusCode: http.statusCode, body: rawBody)
        }

        let decoded = try JSONDecoder().decode(GeminiGenerateResponse.self, from: data)

        if let text = decoded.candidates?
            .first?
            .content
            .parts
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        if let blockReason = decoded.promptFeedback?.blockReason {
            throw GeminiAPIError.requestFailed("Gemini blocked the prompt: \(blockReason)")
        }

        throw GeminiAPIError.emptyResponse
    }

    func streamGenerateReply(
        messages: [ChatMessage],
        apiKey: String,
        model: String,
        systemPrompt: String? = nil,
        safetyPreset: GeminiSafetyPreset = .default
    ) -> AsyncThrowingStream<String, Error> {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestBody = makeGenerateBody(
            messages: messages,
            systemPrompt: systemPrompt,
            safetyPreset: safetyPreset
        )

        return AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    guard !trimmedModel.isEmpty else {
                        throw GeminiAPIError.requestFailed("Model cannot be empty.")
                    }

                    let request = try self.makeGenerateRequest(
                        apiKey: apiKey,
                        model: trimmedModel,
                        body: requestBody,
                        streaming: true
                    )

                    let (bytes, response) = try await self.session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw GeminiAPIError.invalidResponse
                    }

                    guard (200...299).contains(http.statusCode) else {
                        let data = try await self.collectData(from: bytes)
                        let rawBody = String(data: data, encoding: .utf8) ?? "<empty>"
                        throw GeminiAPIError.apiError(statusCode: http.statusCode, body: rawBody)
                    }

                    var hasAnyText = false
                    var currentText = ""
                    var eventLines: [String] = []

                    for try await rawLine in bytes.lines {
                        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

                        if line.isEmpty {
                            if let parsed = self.parseSSEEvent(eventLines) {
                                if let nextText = parsed.text {
                                    hasAnyText = true
                                    currentText = self.mergeStreamingText(current: currentText, incoming: nextText)
                                    continuation.yield(currentText)
                                }
                            }
                            eventLines.removeAll(keepingCapacity: true)
                            continue
                        }

                        if line.hasPrefix(":") {
                            continue
                        }

                        if line.hasPrefix("data:") {
                            var payload = String(line.dropFirst("data:".count))
                            if payload.hasPrefix(" ") {
                                payload.removeFirst()
                            }

                            if payload == "[DONE]" {
                                break
                            }

                            eventLines.append(payload)

                            // Some responses do not separate events with empty lines.
                            // Try to parse as soon as we receive each data chunk.
                            if let parsed = self.parseSSEEvent(eventLines) {
                                if let nextText = parsed.text {
                                    hasAnyText = true
                                    currentText = self.mergeStreamingText(current: currentText, incoming: nextText)
                                    continuation.yield(currentText)
                                }
                                eventLines.removeAll(keepingCapacity: true)
                            }
                        }
                    }

                    if let parsed = self.parseSSEEvent(eventLines) {
                        if let nextText = parsed.text {
                            hasAnyText = true
                            currentText = self.mergeStreamingText(current: currentText, incoming: nextText)
                            continuation.yield(currentText)
                        }
                    }

                    guard hasAnyText else {
                        throw GeminiAPIError.emptyResponse
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                producer.cancel()
            }
        }
    }

    func listGenerateContentModels(apiKey: String, requireStreaming: Bool = false) async throws -> [String] {
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models") else {
            throw GeminiAPIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "pageSize", value: "1000")
        ]

        guard let url = components.url else {
            throw GeminiAPIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw GeminiAPIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let rawBody = String(data: data, encoding: .utf8) ?? "<empty>"
            throw GeminiAPIError.apiError(statusCode: http.statusCode, body: rawBody)
        }

        let decoded = try JSONDecoder().decode(GeminiListModelsResponse.self, from: data)
        let models = (decoded.models ?? [])
            .filter { model in
                guard let methods = model.supportedGenerationMethods else { return false }
                guard methods.contains("generateContent") else { return false }
                if requireStreaming {
                    return methods.contains("streamGenerateContent")
                }
                return true
            }
            .map { model in
                if let slash = model.name.lastIndex(of: "/") {
                    return String(model.name[model.name.index(after: slash)...])
                }
                return model.name
            }
            .sorted()

        return Array(Set(models)).sorted()
    }

    func resolveModelAndAvailableModels(apiKey: String, preferredModel: String) async throws -> (resolvedModel: String, availableModels: [String]) {
        var availableModels = try await listGenerateContentModels(apiKey: apiKey, requireStreaming: true)
        if availableModels.isEmpty {
            availableModels = try await listGenerateContentModels(apiKey: apiKey, requireStreaming: false)
        }
        guard !availableModels.isEmpty else {
            throw GeminiAPIError.requestFailed("No models with generateContent support are available for this API key.")
        }

        if availableModels.contains(preferredModel) {
            return (preferredModel, availableModels)
        }

        let fallbackPriority = [
            "gemini-2.0-flash",
            "gemini-2.0-flash-lite",
            "gemini-1.5-flash",
            "gemini-1.5-pro"
        ]

        for candidate in fallbackPriority where availableModels.contains(candidate) {
            return (candidate, availableModels)
        }

        return (availableModels[0], availableModels)
    }

    private func mapToGeminiContents(messages: [ChatMessage]) -> [GeminiGenerateRequest.Content] {
        messages.map { message in
            GeminiGenerateRequest.Content(
                role: message.role == .assistant ? "model" : "user",
                parts: [.init(text: message.text)]
            )
        }
    }

    private func makeGenerateBody(
        messages: [ChatMessage],
        systemPrompt: String?,
        safetyPreset: GeminiSafetyPreset
    ) -> GeminiGenerateRequest {
        let trimmedPrompt = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction: GeminiGenerateRequest.SystemInstruction?
        if let trimmedPrompt, !trimmedPrompt.isEmpty {
            instruction = GeminiGenerateRequest.SystemInstruction(parts: [.init(text: trimmedPrompt)])
        } else {
            instruction = nil
        }

        return GeminiGenerateRequest(
            contents: mapToGeminiContents(messages: messages),
            systemInstruction: instruction,
            safetySettings: makeSafetySettings(preset: safetyPreset)
        )
    }

    private func makeSafetySettings(preset: GeminiSafetyPreset) -> [GeminiGenerateRequest.SafetySetting]? {
        guard let threshold = preset.thresholdValue else {
            return nil
        }

        let categories = [
            "HARM_CATEGORY_HARASSMENT",
            "HARM_CATEGORY_HATE_SPEECH",
            "HARM_CATEGORY_SEXUALLY_EXPLICIT",
            "HARM_CATEGORY_DANGEROUS_CONTENT"
        ]

        return categories.map { category in
            GeminiGenerateRequest.SafetySetting(category: category, threshold: threshold)
        }
    }

    private func makeGenerateRequest(
        apiKey: String,
        model: String,
        body: GeminiGenerateRequest,
        streaming: Bool
    ) throws -> URLRequest {
        let endpoint = streaming ? "streamGenerateContent" : "generateContent"
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):\(endpoint)") else {
            throw GeminiAPIError.invalidURL
        }

        if streaming {
            components.queryItems = [
                URLQueryItem(name: "key", value: apiKey),
                URLQueryItem(name: "alt", value: "sse")
            ]
        } else {
            components.queryItems = [
                URLQueryItem(name: "key", value: apiKey)
            ]
        }

        guard let url = components.url else {
            throw GeminiAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if streaming {
            request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    private struct ParsedStreamEvent {
        let text: String?
    }

    private func parseSSEEvent(_ eventLines: [String]) -> ParsedStreamEvent? {
        guard !eventLines.isEmpty else { return nil }
        let payload = eventLines.joined(separator: "\n")
        guard payload != "[DONE]" else { return nil }

        if let parsed = parseStreamPayload(payload) {
            return parsed
        }

        // Some providers split one JSON payload into several data-lines.
        // Try each line independently as a fallback, merging all parsed chunks.
        var mergedText = ""
        var didParseAnyLine = false
        for line in eventLines {
            if let parsed = parseStreamPayload(line) {
                didParseAnyLine = true
                if let nextText = parsed.text {
                    mergedText = mergeStreamingText(current: mergedText, incoming: nextText)
                }
            }
        }

        guard didParseAnyLine else { return nil }
        return ParsedStreamEvent(text: mergedText.isEmpty ? nil : mergedText)
    }

    private func parseStreamPayload(_ payload: String) -> ParsedStreamEvent? {
        guard let data = payload.data(using: .utf8) else { return nil }

        if let decoded = try? JSONDecoder().decode(GeminiGenerateResponse.self, from: data) {
            let text = decoded.candidates?
                .first?
                .content
                .parts
                .compactMap(\.text)
                .joined(separator: "\n")
            let normalized = (text?.isEmpty == false) ? text : nil
            return ParsedStreamEvent(text: normalized)
        }

        if let decodedArray = try? JSONDecoder().decode([GeminiGenerateResponse].self, from: data) {
            var mergedText = ""
            var hasText = false

            for item in decodedArray {
                let text = item.candidates?
                    .first?
                    .content
                    .parts
                    .compactMap(\.text)
                    .joined(separator: "\n")
                if let text, !text.isEmpty {
                    hasText = true
                    mergedText = mergeStreamingText(current: mergedText, incoming: text)
                }
            }

            if hasText {
                return ParsedStreamEvent(text: mergedText.isEmpty ? nil : mergedText)
            }
        }

        return nil
    }

    private func mergeStreamingText(current: String, incoming: String) -> String {
        if incoming == current {
            return current
        }
        if incoming.hasPrefix(current) {
            return incoming
        }
        if current.hasPrefix(incoming) {
            return current
        }
        return current + incoming
    }
}
