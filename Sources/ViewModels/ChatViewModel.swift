import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    enum ConnectionStatus {
        case notConfigured
        case notChecked
        case checking
        case connected(modelsCount: Int)
        case failed(message: String)
    }

    @Published var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published var isSending: Bool = false
    @Published var isLoadingModels: Bool = false
    @Published var errorMessage: String?
    @Published var availableModels: [String] = []
    @Published var model: String {
        didSet {
            UserDefaults.standard.set(model, forKey: Self.modelDefaultsKey)
        }
    }
    @Published var systemPrompt: String {
        didSet {
            UserDefaults.standard.set(systemPrompt, forKey: Self.systemPromptDefaultsKey)
        }
    }
    @Published var safetyPreset: GeminiSafetyPreset {
        didSet {
            UserDefaults.standard.set(safetyPreset.rawValue, forKey: Self.safetyPresetDefaultsKey)
        }
    }
    @Published var apiKey: String {
        didSet {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let oldTrimmed = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                connectionStatus = .notConfigured
            } else if trimmed != oldTrimmed {
                connectionStatus = .notChecked
            }
        }
    }
    @Published var connectionStatus: ConnectionStatus = .notConfigured
    @Published private(set) var chatHistory: [ChatThreadSummary] = []
    @Published private(set) var currentChatID: UUID?

    private let client: GeminiAPIClient
    private let localStore: LocalStore
    private let historyStore: ChatHistoryStore
    private var currentSendTask: Task<Void, Never>?
    private var historySaveTask: Task<Void, Never>?
    private var historyThreads: [ChatThread] = []

    private static let apiKeyAccount = "gemini-api-key"
    private static let modelDefaultsKey = "gemini-model"
    private static let systemPromptDefaultsKey = "gemini-system-prompt"
    private static let safetyPresetDefaultsKey = "gemini-safety-preset"
    private static let defaultModel = "gemini-2.0-flash"
    private static let historySaveDebounceNanoseconds: UInt64 = 900_000_000

    init(
        client: GeminiAPIClient = GeminiAPIClient(),
        localStore: LocalStore = LocalStore(service: "GeminiChatMac"),
        historyStore: ChatHistoryStore = ChatHistoryStore()
    ) {
        self.client = client
        self.localStore = localStore
        self.historyStore = historyStore

        let savedModel = UserDefaults.standard.string(forKey: Self.modelDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let savedModel, !savedModel.isEmpty, savedModel != "gemini-3" {
            self.model = savedModel
        } else {
            self.model = Self.defaultModel
        }

        self.systemPrompt = UserDefaults.standard.string(forKey: Self.systemPromptDefaultsKey) ?? ""
        let savedSafetyPreset = UserDefaults.standard.string(forKey: Self.safetyPresetDefaultsKey)
        self.safetyPreset = GeminiSafetyPreset(rawValue: savedSafetyPreset ?? "") ?? .default

        do {
            self.apiKey = try localStore.readString(account: Self.apiKeyAccount) ?? ""
            self.connectionStatus = self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .notConfigured : .notChecked
        } catch {
            self.apiKey = ""
            self.connectionStatus = .failed(message: error.localizedDescription)
            self.errorMessage = error.localizedDescription
        }

        loadHistory()
    }

    var canSend: Bool {
        let hasDraft = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasDraft && hasKey && !isSending
    }

    var canManageHistory: Bool {
        !isSending
    }

    func saveAPIKey() {
        persistAPIKey(showErrors: true)
    }

    func persistAPIKey(showErrors: Bool = false) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if trimmed.isEmpty {
                try localStore.deleteString(account: Self.apiKeyAccount)
                connectionStatus = .notConfigured
            } else {
                try localStore.saveString(trimmed, account: Self.apiKeyAccount)
            }
            if showErrors {
                errorMessage = nil
            }
        } catch {
            if showErrors {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadAvailableModels(autoSelect: Bool = false) async {
        guard !isLoadingModels else { return }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            connectionStatus = .notConfigured
            errorMessage = "Please enter your Gemini API key."
            return
        }

        isLoadingModels = true
        connectionStatus = .checking
        defer { isLoadingModels = false }

        do {
            var models = try await client.listGenerateContentModels(apiKey: trimmedKey, requireStreaming: true)
            if models.isEmpty {
                models = try await client.listGenerateContentModels(apiKey: trimmedKey, requireStreaming: false)
            }
            availableModels = models
            connectionStatus = .connected(modelsCount: models.count)
            errorMessage = nil

            if autoSelect, !models.contains(model), let first = models.first {
                model = first
            }
        } catch {
            connectionStatus = .failed(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func clearChat() {
        startNewChat()
    }

    func startNewChat() {
        guard canManageHistory else { return }
        cancelResponse()
        deduplicateEmptyThreads(preferCurrent: true)

        if messages.isEmpty {
            draft = ""
            errorMessage = nil
            rebuildHistorySummaries()
            persistHistoryNow()
            return
        }

        if let existingEmptyID = historyThreads.first(where: { $0.messages.isEmpty })?.id {
            openChat(id: existingEmptyID)
            return
        }

        let thread = createEmptyThread()
        historyThreads.insert(thread, at: 0)
        currentChatID = thread.id
        messages = []
        draft = ""
        errorMessage = nil

        rebuildHistorySummaries()
        persistHistoryNow()
    }

    func openChat(id: UUID) {
        guard canManageHistory else { return }
        guard let index = historyThreads.firstIndex(where: { $0.id == id }) else { return }

        currentChatID = id
        messages = historyThreads[index].messages
        draft = ""
        errorMessage = nil

        rebuildHistorySummaries()
        persistHistoryNow()
    }

    func deleteChat(id: UUID) {
        guard canManageHistory else { return }

        let removedCurrent = currentChatID == id
        historyThreads.removeAll { $0.id == id }

        if historyThreads.isEmpty {
            let thread = createEmptyThread()
            historyThreads = [thread]
            currentChatID = thread.id
            messages = []
            draft = ""
        } else if removedCurrent {
            let next = historyThreads.sorted { $0.updatedAt > $1.updatedAt }.first!
            currentChatID = next.id
            messages = next.messages
            draft = ""
        }

        rebuildHistorySummaries()
        persistHistoryNow()
    }

    func persistHistory() {
        historySaveTask?.cancel()
        syncCurrentThread(updateTimestamp: true, updatePublishedHistory: true)
        persistHistoryNow()
    }

    func startSend() {
        guard currentSendTask == nil else { return }

        currentSendTask = Task { [weak self] in
            guard let self else { return }
            await self.send()
            await MainActor.run {
                self.currentSendTask = nil
            }
        }
    }

    func cancelResponse() {
        currentSendTask?.cancel()
        errorMessage = nil
    }

    func send() async {
        guard !isSending else { return }

        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            errorMessage = "Please enter your Gemini API key."
            return
        }

        let userMessage = ChatMessage(role: .user, text: trimmedDraft)
        messages.append(userMessage)
        syncCurrentThread(updateTimestamp: true, updatePublishedHistory: false)
        scheduleHistorySave()

        draft = ""
        errorMessage = nil

        apiKey = trimmedKey
        persistAPIKey(showErrors: true)

        isSending = true
        defer {
            isSending = false
            syncCurrentThread(updateTimestamp: true, updatePublishedHistory: true)
            persistHistoryNow()
        }

        let selectedModel = model
        let selectedSystemPrompt = systemPrompt
        let selectedSafetyPreset = safetyPreset

        do {
            let requestMessages = messages
            let usedPromptFallback = try await sendAssistantResponseWithPromptFallback(
                sourceMessages: requestMessages,
                apiKey: trimmedKey,
                model: selectedModel,
                systemPrompt: selectedSystemPrompt,
                safetyPreset: selectedSafetyPreset
            )
            if usedPromptFallback {
                errorMessage = "System prompt is not supported for \(selectedModel). Message was sent without it."
            }
        } catch GeminiAPIError.apiError(let statusCode, _) where statusCode == 404 {
            do {
                let oldModel = selectedModel
                let resolution = try await client.resolveModelAndAvailableModels(
                    apiKey: trimmedKey,
                    preferredModel: oldModel
                )
                let resolvedModel = resolution.resolvedModel
                model = resolvedModel
                availableModels = resolution.availableModels

                let requestMessages = messages
                let usedPromptFallback = try await sendAssistantResponseWithPromptFallback(
                    sourceMessages: requestMessages,
                    apiKey: trimmedKey,
                    model: resolvedModel,
                    systemPrompt: selectedSystemPrompt,
                    safetyPreset: selectedSafetyPreset
                )
                if usedPromptFallback {
                    errorMessage = "Model \(oldModel) is unavailable for your key. Switched to \(resolvedModel). System prompt is unsupported and was skipped."
                } else {
                    errorMessage = "Model \(oldModel) is unavailable for your key. Switched to \(resolvedModel)."
                }
            } catch {
                if error is CancellationError {
                    return
                }
                errorMessage = error.localizedDescription
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func appendAssistantPlaceholder(modelName: String) -> UUID {
        let message = ChatMessage(role: .assistant, text: "", modelName: modelName)
        messages.append(message)
        syncCurrentThread(updateTimestamp: true, updatePublishedHistory: false)
        scheduleHistorySave()
        return message.id
    }

    private func updateMessage(id: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let existing = messages[index]
        messages[index] = ChatMessage(
            id: existing.id,
            role: existing.role,
            text: text,
            modelName: existing.modelName,
            createdAt: existing.createdAt
        )
        syncCurrentThread(updateTimestamp: false, updatePublishedHistory: false)
        scheduleHistorySave()
    }

    private func removeMessage(id: UUID) {
        messages.removeAll { $0.id == id }
        syncCurrentThread(updateTimestamp: true, updatePublishedHistory: true)
        scheduleHistorySave()
    }

    private func currentMessageText(id: UUID) -> String {
        messages.first(where: { $0.id == id })?.text ?? ""
    }

    private func streamAssistantReply(
        sourceMessages: [ChatMessage],
        apiKey: String,
        model: String,
        systemPrompt: String?,
        safetyPreset: GeminiSafetyPreset,
        assistantID: UUID
    ) async throws {
        var didReceiveText = false
        var lastPartialText = ""
        var lastChunkAt: Date?
        var smoothedCharsPerSecond: Double = 52

        let stream = await client.streamGenerateReply(
            messages: sourceMessages,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            safetyPreset: safetyPreset
        )

        do {
            for try await partialText in stream {
                try Task.checkCancellation()
                didReceiveText = true

                let now = Date()
                let nextRate = measuredStreamingRate(
                    previousText: lastPartialText,
                    nextText: partialText,
                    previousChunkAt: lastChunkAt,
                    now: now,
                    previousRate: smoothedCharsPerSecond
                )

                lastPartialText = partialText
                lastChunkAt = now
                smoothedCharsPerSecond = nextRate

                await animateMessageToTarget(
                    id: assistantID,
                    targetText: partialText,
                    incomingCharsPerSecond: smoothedCharsPerSecond
                )
            }
        } catch is CancellationError {
            if !didReceiveText {
                removeMessage(id: assistantID)
            }
            return
        } catch {
            if let apiError = error as? GeminiAPIError {
                switch apiError {
                case .apiError, .requestFailed:
                    if !didReceiveText {
                        removeMessage(id: assistantID)
                    }
                    throw apiError
                default:
                    break
                }
            }

            do {
                let fullReply = try await client.generateReply(
                    messages: sourceMessages,
                    apiKey: apiKey,
                    model: model,
                    systemPrompt: systemPrompt,
                    safetyPreset: safetyPreset
                )
                await animateAssistantText(fullReply, assistantID: assistantID)
                return
            } catch {
                if !didReceiveText {
                    removeMessage(id: assistantID)
                }
                throw error
            }
        }

        if !didReceiveText {
            do {
                let fullReply = try await client.generateReply(
                    messages: sourceMessages,
                    apiKey: apiKey,
                    model: model,
                    systemPrompt: systemPrompt,
                    safetyPreset: safetyPreset
                )
                await animateAssistantText(fullReply, assistantID: assistantID)
            } catch {
                removeMessage(id: assistantID)
                throw error
            }
        }
    }

    private func sendAssistantResponseWithPromptFallback(
        sourceMessages: [ChatMessage],
        apiKey: String,
        model: String,
        systemPrompt: String?,
        safetyPreset: GeminiSafetyPreset
    ) async throws -> Bool {
        let normalizedPrompt = normalizedSystemPrompt(systemPrompt)

        do {
            let assistantID = appendAssistantPlaceholder(modelName: model)
            try await streamAssistantReply(
                sourceMessages: sourceMessages,
                apiKey: apiKey,
                model: model,
                systemPrompt: normalizedPrompt,
                safetyPreset: safetyPreset,
                assistantID: assistantID
            )
            return false
        } catch {
            guard shouldRetryWithoutSystemPrompt(error: error, hadSystemPrompt: normalizedPrompt != nil) else {
                throw error
            }

            try Task.checkCancellation()
            let assistantID = appendAssistantPlaceholder(modelName: model)
            try await streamAssistantReply(
                sourceMessages: sourceMessages,
                apiKey: apiKey,
                model: model,
                systemPrompt: nil,
                safetyPreset: safetyPreset,
                assistantID: assistantID
            )
            return true
        }
    }

    private func normalizedSystemPrompt(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func shouldRetryWithoutSystemPrompt(error: Error, hadSystemPrompt: Bool) -> Bool {
        guard hadSystemPrompt else { return false }
        guard case GeminiAPIError.apiError(let statusCode, let body) = error else { return false }
        guard statusCode == 400 else { return false }

        let normalizedBody = body.lowercased()
        return normalizedBody.contains("developer instruction is not enabled")
            || normalizedBody.contains("system instruction is not enabled")
            || normalizedBody.contains("system_instruction")
    }

    private func animateAssistantText(_ text: String, assistantID: UUID) async {
        await animateMessageToTarget(id: assistantID, targetText: text, incomingCharsPerSecond: 120)
    }

    private func animateMessageToTarget(
        id: UUID,
        targetText: String,
        incomingCharsPerSecond: Double
    ) async {
        guard !targetText.isEmpty else {
            updateMessage(id: id, text: targetText)
            return
        }

        let currentText = currentMessageText(id: id)
        if currentText == targetText {
            return
        }

        let commonPrefixLength = zip(currentText, targetText).prefix { $0 == $1 }.count
        var rendered = String(targetText.prefix(commonPrefixLength))
        if rendered != currentText {
            updateMessage(id: id, text: rendered)
        }

        var chunk = ""
        let suffix = targetText.dropFirst(commonPrefixLength)
        let pacing = animationPacing(forIncomingCharsPerSecond: incomingCharsPerSecond)
        let targetChunkSize = pacing.chunkSize
        let sleepNanoseconds = pacing.sleepNanoseconds

        for character in suffix {
            if Task.isCancelled {
                return
            }
            chunk.append(character)

            if chunk.count >= targetChunkSize || character == "\n" {
                rendered += chunk
                updateMessage(id: id, text: rendered)
                chunk.removeAll(keepingCapacity: true)
                if sleepNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: sleepNanoseconds)
                }
            }
        }

        if !chunk.isEmpty {
            rendered += chunk
            updateMessage(id: id, text: rendered)
        }
    }

    private func measuredStreamingRate(
        previousText: String,
        nextText: String,
        previousChunkAt: Date?,
        now: Date,
        previousRate: Double
    ) -> Double {
        let appendedCount = max(1, nextText.count - previousText.count)
        guard let previousChunkAt else {
            return previousRate
        }

        let delta = max(0.03, now.timeIntervalSince(previousChunkAt))
        let instantRate = Double(appendedCount) / delta
        let clampedRate = min(max(instantRate, 8), 260)

        // EMA keeps animation stable and still reactive to faster/slower streams.
        return (previousRate * 0.72) + (clampedRate * 0.28)
    }

    private func animationPacing(forIncomingCharsPerSecond rate: Double) -> (chunkSize: Int, sleepNanoseconds: UInt64) {
        let clampedRate = min(max(rate, 10), 260)

        let chunkSize: Int
        switch clampedRate {
        case ..<28:
            chunkSize = 1
        case ..<64:
            chunkSize = 2
        case ..<120:
            chunkSize = 3
        case ..<190:
            chunkSize = 5
        default:
            chunkSize = 7
        }

        let rawDelay = (Double(chunkSize) / clampedRate) * 1_000_000_000
        let cappedDelay = min(max(rawDelay, 0), 32_000_000)
        return (chunkSize, UInt64(cappedDelay))
    }

    private func loadHistory() {
        do {
            historyThreads = try historyStore.loadThreads()
            deduplicateEmptyThreads(preferCurrent: false)
            if historyThreads.isEmpty {
                startFreshHistory()
                return
            }
        } catch {
            errorMessage = "Failed to load chat history: \(error.localizedDescription)"
            startFreshHistory()
            return
        }

        let sorted = historyThreads.sorted { $0.updatedAt > $1.updatedAt }
        if let current = sorted.first {
            currentChatID = current.id
            messages = current.messages
        } else {
            startFreshHistory()
            return
        }

        rebuildHistorySummaries()
    }

    private func startFreshHistory() {
        let thread = createEmptyThread()
        historyThreads = [thread]
        currentChatID = thread.id
        messages = []
        draft = ""
        rebuildHistorySummaries()
        persistHistoryNow()
    }

    private func createEmptyThread() -> ChatThread {
        let now = Date()
        return ChatThread(
            title: "New Chat",
            messages: [],
            createdAt: now,
            updatedAt: now
        )
    }

    private func deduplicateEmptyThreads(preferCurrent: Bool) {
        let emptyThreads = historyThreads.filter { $0.messages.isEmpty }
        guard emptyThreads.count > 1 else { return }

        let keepID: UUID
        if preferCurrent,
           let currentChatID,
           messages.isEmpty,
           emptyThreads.contains(where: { $0.id == currentChatID }) {
            keepID = currentChatID
        } else {
            keepID = emptyThreads.max(by: { $0.updatedAt < $1.updatedAt })?.id ?? emptyThreads[0].id
        }

        historyThreads.removeAll { $0.messages.isEmpty && $0.id != keepID }
    }

    private func syncCurrentThread(updateTimestamp: Bool, updatePublishedHistory: Bool) {
        if currentChatID == nil {
            let thread = createEmptyThread()
            historyThreads.insert(thread, at: 0)
            currentChatID = thread.id
        }

        guard let currentChatID else { return }
        let now = Date()

        if let index = historyThreads.firstIndex(where: { $0.id == currentChatID }) {
            historyThreads[index].messages = messages
            historyThreads[index].title = historyTitle(from: messages)
            if updateTimestamp {
                historyThreads[index].updatedAt = now
            }
        } else {
            let thread = ChatThread(
                id: currentChatID,
                title: historyTitle(from: messages),
                messages: messages,
                createdAt: now,
                updatedAt: now
            )
            historyThreads.insert(thread, at: 0)
        }

        if updatePublishedHistory {
            rebuildHistorySummaries()
        }
    }

    private func historyTitle(from messages: [ChatMessage]) -> String {
        guard let firstUserText = messages
            .first(where: { $0.role == .user })?
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !firstUserText.isEmpty else {
            return "New Chat"
        }

        let firstLine = firstUserText.components(separatedBy: .newlines).first ?? firstUserText
        let compact = normalizedWhitespace(firstLine)
        let result = String(compact.prefix(64)).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "New Chat" : result
    }

    private func previewText(from messages: [ChatMessage]) -> String {
        guard let lastNonEmpty = messages
            .last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .text else {
            return "No messages yet"
        }

        let singleLine = normalizedWhitespace(lastNonEmpty)
        if singleLine.isEmpty {
            return "No messages yet"
        }
        return String(singleLine.prefix(90))
    }

    private func normalizedWhitespace(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func rebuildHistorySummaries() {
        let sorted = historyThreads.sorted { $0.updatedAt > $1.updatedAt }
        chatHistory = sorted.map { thread in
            ChatThreadSummary(
                id: thread.id,
                title: thread.title,
                preview: previewText(from: thread.messages),
                updatedAt: thread.updatedAt
            )
        }
    }

    private func persistHistoryNow() {
        deduplicateEmptyThreads(preferCurrent: true)
        do {
            try historyStore.saveThreads(historyThreads)
        } catch {
            errorMessage = "Failed to save chat history: \(error.localizedDescription)"
        }
    }

    private func scheduleHistorySave() {
        historySaveTask?.cancel()
        historySaveTask = Task {
            try? await Task.sleep(nanoseconds: Self.historySaveDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.syncCurrentThread(updateTimestamp: false, updatePublishedHistory: false)
                self.persistHistoryNow()
            }
        }
    }
}
