import Foundation

final class ChatHistoryStore {
    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        appName: String = "GeminiChatMac",
        fileName: String = "chat-history.json",
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder.dateEncodingStrategy = .iso8601

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.fileURL = appSupport
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    func loadThreads() throws -> [ChatThread] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            return []
        }

        return try decoder.decode([ChatThread].self, from: data)
    }

    func saveThreads(_ threads: [ChatThread]) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let data = try encoder.encode(threads)
        try data.write(to: fileURL, options: [.atomic])
    }
}
