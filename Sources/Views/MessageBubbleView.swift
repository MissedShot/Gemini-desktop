import SwiftUI
import AppKit

struct MessageBubbleView: View {
    let message: ChatMessage
    @State private var didCopy: Bool = false
    @State private var isCopyHovered: Bool = false
    @State private var copyResetTask: Task<Void, Never>?

    private var isAssistant: Bool {
        message.role == .assistant
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if !isAssistant {
                Spacer(minLength: 72)
            }

            bubbleCard

            if isAssistant {
                Spacer(minLength: 72)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private var bubbleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(roleTitle, systemImage: roleIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let assistantModelLabel {
                    Text(assistantModelLabel)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button {
                        copyMessageText()
                    } label: {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.caption.weight(.semibold))
                            .frame(width: 20, height: 20)
                            .foregroundStyle(didCopy ? Color.accentColor : Color.secondary)
                            .animation(.easeOut(duration: 0.16), value: didCopy)
                    }
                    .buttonStyle(
                        MessageCopyButtonStyle(
                            isHovered: isCopyHovered,
                            isActive: didCopy
                        )
                    )
                    .help("Copy")
                    .disabled(copyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.14)) {
                            isCopyHovered = hovering
                        }
                    }
                }
            }

            if isAssistant && message.text.isEmpty {
                TypingIndicatorView()
            } else if isAssistant {
                Text(cleanedAssistantText(message.text))
                    .textSelection(.enabled)
                    .lineSpacing(3)
            } else {
                Text(message.text)
                    .textSelection(.enabled)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isAssistant ? Color(nsColor: .textBackgroundColor) : Color.accentColor.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isAssistant ? Color.secondary.opacity(0.14) : Color.accentColor.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isAssistant ? 0.04 : 0.08), radius: 6, x: 0, y: 2)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") {
                copyMessageText()
            }
            .disabled(copyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onDisappear {
            copyResetTask?.cancel()
        }
    }

    private var roleTitle: String {
        isAssistant ? "Gemini" : "You"
    }

    private var roleIcon: String {
        isAssistant ? "sparkles" : "person"
    }

    private var assistantModelLabel: String? {
        guard isAssistant else { return nil }
        let trimmed = message.modelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var copyText: String {
        if isAssistant {
            return cleanedAssistantText(message.text)
        }
        return message.text
    }

    private func copyMessageText() {
        let value = copyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)

        copyResetTask?.cancel()
        didCopy = true

        copyResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                didCopy = false
            }
        }
    }

    private func cleanedAssistantText(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")

        let lines = normalized.components(separatedBy: "\n").map { rawLine -> String in
            var line = rawLine

            line = line.replacingOccurrences(
                of: #"^\s{0,3}#{1,6}\s*"#,
                with: "",
                options: .regularExpression
            )

            line = line.replacingOccurrences(
                of: #"^\s*[*+-]\s+"#,
                with: "• ",
                options: .regularExpression
            )

            line = stripInlineMarkdown(from: line)

            return line
        }

        return lines.joined(separator: "\n")
    }

    private func stripInlineMarkdown(from line: String) -> String {
        var result = line

        result = result.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#,
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"__(.+?)__"#,
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\*(.+?)\*"#,
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"_(.+?)_"#,
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: "$1",
            options: .regularExpression
        )

        return result
    }

    private struct MessageCopyButtonStyle: ButtonStyle {
        let isHovered: Bool
        let isActive: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(
                    Circle()
                        .fill(backgroundColor)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.secondary.opacity(isHovered ? 0.34 : 0.18), lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.9 : (isHovered ? 1.06 : (isActive ? 1.03 : 1.0)))
                .animation(.spring(response: 0.2, dampingFraction: 0.72), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.14), value: isHovered)
                .animation(.easeOut(duration: 0.14), value: isActive)
        }

        private var backgroundColor: Color {
            if isActive {
                return Color.accentColor.opacity(0.14)
            }
            if isHovered {
                return Color.secondary.opacity(0.12)
            }
            return Color.clear
        }
    }
}

private struct TypingIndicatorView: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.9))
                    .frame(width: 7, height: 7)
                    .scaleEffect(animate ? 0.65 : 1.0)
                    .opacity(animate ? 0.35 : 0.9)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.14),
                        value: animate
                    )
            }
        }
        .padding(.vertical, 2)
        .onAppear {
            animate = true
        }
        .accessibilityLabel("Typing")
    }
}
