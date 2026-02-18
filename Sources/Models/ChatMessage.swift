import Foundation

enum ChatRole: String, Codable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let role: ChatRole
    let text: String
    let modelName: String?
    let createdAt: Date

    init(id: UUID = UUID(), role: ChatRole, text: String, modelName: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.modelName = modelName
        self.createdAt = createdAt
    }
}
