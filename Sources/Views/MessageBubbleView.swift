import SwiftUI
import AppKit

struct MessageBubbleView: View {
    let message: ChatMessage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didCopy = false
    @State private var isHovered = false
    @State private var copyResetTask: Task<Void, Never>?

    private var isAssistant: Bool {
        message.role == .assistant
    }

    var body: some View {
        Group {
            if isAssistant {
                assistantMessage
            } else {
                userMessage
            }
        }
        .frame(maxWidth: .infinity)
        .onHover { isHovered = $0 }
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

    private var assistantMessage: some View {
        HStack(alignment: .top, spacing: 12) {
            assistantMark

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Text("Gemini")
                        .font(.callout.weight(.semibold))

                    if let assistantModelLabel {
                        Text("·")
                            .foregroundStyle(.tertiary)

                        Text(assistantModelLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    messageActions(copyLabel: "Copy response")
                }

                if message.text.isEmpty {
                    TypingIndicatorView(reduceMotion: reduceMotion)
                } else {
                    MarkdownContentView(markdown: message.text)
                        .tint(AppTheme.accentBlue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private var userMessage: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 72)

            VStack(alignment: .trailing, spacing: 6) {
                Text(message.text)
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 580, alignment: .leading)
                    .background(AppTheme.accentBlue.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.accentBlue.opacity(0.16), lineWidth: 1)
                    }

                HStack(spacing: 7) {
                    Text("You")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    messageActions(copyLabel: "Copy message")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var assistantMark: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(AppTheme.accentGradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }

    private func messageActions(copyLabel: String) -> some View {
        HStack(spacing: 5) {
            Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)

            Button {
                copyMessageText()
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(MessageActionButtonStyle(isActive: didCopy))
            .help(didCopy ? "Copied" : copyLabel)
            .accessibilityLabel(didCopy ? "Copied" : copyLabel)
            .disabled(copyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .opacity(isHovered || didCopy ? 1 : 0.48)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
    }

    private var assistantModelLabel: String? {
        guard isAssistant else { return nil }
        let raw = message.modelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }

        return raw
            .replacingOccurrences(of: "models/", with: "")
            .replacingOccurrences(of: "gemini-", with: "")
            .split(separator: "-")
            .map { part in
                part.first?.isNumber == true ? String(part) : part.capitalized
            }
            .joined(separator: " ")
    }

    private var copyText: String {
        message.text
    }

    private func copyMessageText() {
        let value = copyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)

        copyResetTask?.cancel()
        didCopy = true

        copyResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                didCopy = false
            }
        }
    }
}

private struct MessageActionButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? AppTheme.accentBlue : Color.secondary)
            .background(
                isActive ? AppTheme.accentBlue.opacity(0.12) : Color.secondary.opacity(configuration.isPressed ? 0.14 : 0.06),
                in: Circle()
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

private struct TypingIndicatorView: View {
    let reduceMotion: Bool
    @State private var animate = false

    var body: some View {
        HStack(spacing: 8) {
            if reduceMotion {
                ProgressView()
                    .controlSize(.small)
            } else {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(AppTheme.accentBlue.opacity(0.8))
                            .frame(width: 6, height: 6)
                            .offset(y: animate ? -2 : 2)
                            .opacity(animate ? 0.45 : 1)
                            .animation(
                                .easeInOut(duration: 0.55)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.12),
                                value: animate
                            )
                    }
                }
                .onAppear {
                    animate = true
                }
            }

            Text("Thinking…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gemini is responding")
    }
}
