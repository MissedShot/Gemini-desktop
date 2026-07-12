import SwiftUI

enum AppTheme {
    static let conversationMaxWidth: CGFloat = 820
    static let composerMaxWidth: CGFloat = 820
    static let sidebarIdealWidth: CGFloat = 264

    static let accentBlue = Color(red: 0.30, green: 0.48, blue: 0.98)
    static let accentViolet = Color(red: 0.58, green: 0.36, blue: 0.96)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentBlue, accentViolet],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var workspaceBackground: Color {
        Color(nsColor: .textBackgroundColor)
    }

    static var sidebarBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var elevatedSurface: Color {
        Color(nsColor: .controlBackgroundColor)
    }
}

extension ChatViewModel.ConnectionStatus {
    var title: String {
        switch self {
        case .notConfigured:
            return "Not configured"
        case .notChecked:
            return "Ready to check"
        case .checking:
            return "Checking connection…"
        case .connected(let modelsCount):
            return "Connected · \(modelsCount) models"
        case .failed:
            return "Connection failed"
        }
    }

    var compactTitle: String {
        switch self {
        case .notConfigured:
            return "Set up Gemini"
        case .notChecked:
            return "Not checked"
        case .checking:
            return "Checking"
        case .connected:
            return "Connected"
        case .failed:
            return "Needs attention"
        }
    }

    var systemImage: String {
        switch self {
        case .connected:
            return "checkmark.circle.fill"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .notConfigured:
            return "key.fill"
        case .notChecked:
            return "circle.dotted"
        }
    }

    var tint: Color {
        switch self {
        case .connected:
            return .green
        case .checking:
            return .orange
        case .failed:
            return .red
        case .notConfigured, .notChecked:
            return .secondary
        }
    }

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}
