import Foundation

enum GeminiSafetyPreset: String, CaseIterable, Identifiable {
    case `default` = "default"
    case strict = "strict"
    case balanced = "balanced"
    case relaxed = "relaxed"
    case off = "off"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default:
            return "Default"
        case .strict:
            return "Strict"
        case .balanced:
            return "Balanced"
        case .relaxed:
            return "Relaxed"
        case .off:
            return "Off"
        }
    }

    var description: String {
        switch self {
        case .default:
            return "Use Gemini default safety behavior"
        case .strict:
            return "Block low-risk and above"
        case .balanced:
            return "Block medium-risk and above"
        case .relaxed:
            return "Block only high-risk content"
        case .off:
            return "Disable configurable safety filters"
        }
    }

    var thresholdValue: String? {
        switch self {
        case .default:
            return nil
        case .strict:
            return "BLOCK_LOW_AND_ABOVE"
        case .balanced:
            return "BLOCK_MEDIUM_AND_ABOVE"
        case .relaxed:
            return "BLOCK_ONLY_HIGH"
        case .off:
            return "OFF"
        }
    }
}
