import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel

    @State private var revealAPIKey = false
    @State private var apiKeySaveTask: Task<Void, Never>?

    var body: some View {
        TabView {
            connectionPane
                .tabItem {
                    Label("Connection", systemImage: "key.fill")
                }

            behaviorPane
                .tabItem {
                    Label("Behavior", systemImage: "text.bubble.fill")
                }

            safetyPane
                .tabItem {
                    Label("Safety", systemImage: "shield.lefthalf.filled")
                }
        }
        .frame(width: 620, height: 500)
        .onChange(of: viewModel.apiKey) { _, _ in
            scheduleAPIKeyPersist()
        }
        .onDisappear {
            apiKeySaveTask?.cancel()
            revealAPIKey = false
            viewModel.persistAPIKey()
        }
    }

    private var connectionPane: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "key.horizontal.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.accentGradient)
                            .frame(width: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gemini API key")
                                .font(.headline)
                            Text("Used only to connect this Mac to the Gemini API.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Group {
                        if revealAPIKey {
                            TextField("Paste your API key", text: $viewModel.apiKey)
                        } else {
                            SecureField("Paste your API key", text: $viewModel.apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    HStack {
                        Toggle("Show key", isOn: $revealAPIKey)
                            .toggleStyle(.switch)

                        Spacer()

                        Button("Remove", role: .destructive) {
                            viewModel.apiKey = ""
                            viewModel.saveAPIKey()
                        }
                        .disabled(!hasAPIKey)

                        Button("Save & Check") {
                            viewModel.saveAPIKey()
                            guard hasAPIKey else { return }
                            Task {
                                await viewModel.loadAvailableModels(autoSelect: true)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasAPIKey || viewModel.isLoadingModels)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Status") {
                LabeledContent("Connection") {
                    HStack(spacing: 7) {
                        if viewModel.isLoadingModels {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: viewModel.connectionStatus.systemImage)
                        }

                        Text(viewModel.connectionStatus.title)
                    }
                    .foregroundStyle(viewModel.connectionStatus.tint)
                }

                LabeledContent("Selected model") {
                    Text(friendlyModelName(viewModel.model))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if case .failed(let message) = viewModel.connectionStatus {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Check Connection") {
                    Task {
                        await viewModel.loadAvailableModels(autoSelect: true)
                    }
                }
                .disabled(!hasAPIKey || viewModel.isLoadingModels)
            }

            Section {
                Label("The key is stored locally in this app’s preferences and is never included in chat history.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            if hasAPIKey && viewModel.availableModels.isEmpty {
                await viewModel.loadAvailableModels(autoSelect: true)
            }
        }
    }

    private var behaviorPane: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "quote.bubble.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.accentGradient)
                            .frame(width: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("System prompt")
                                .font(.headline)
                            Text("Set the voice, role, or rules Gemini should follow.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SystemPromptEditor(
                        text: $viewModel.systemPrompt,
                        placeholder: "For example: Be concise, practical, and explain technical terms…"
                    )
                    .frame(height: 220)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }

                    HStack {
                        Text("\(viewModel.systemPrompt.count) characters")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Clear") {
                            viewModel.systemPrompt = ""
                        }
                        .disabled(viewModel.systemPrompt.isEmpty)
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("The prompt applies to future responses in every conversation. Some models may not support it.")
            }
        }
        .formStyle(.grouped)
    }

    private var safetyPane: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "shield.checkered")
                            .font(.title3)
                            .foregroundStyle(AppTheme.accentGradient)
                            .frame(width: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Safety level")
                                .font(.headline)
                            Text("Choose how conservatively Gemini filters responses.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("Safety level", selection: $viewModel.safetyPreset) {
                        ForEach(GeminiSafetyPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                .padding(.vertical, 4)
            }

            Section("Current selection") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.safetyPreset.title)
                        .font(.headline)
                    Text(viewModel.safetyPreset.description)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 3)
            }

            Section {
                Label("Gemini always enforces its core harm protections, regardless of this setting.", systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var hasAPIKey: Bool {
        !viewModel.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func scheduleAPIKeyPersist() {
        apiKeySaveTask?.cancel()
        apiKeySaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                viewModel.persistAPIKey()
            }
        }
    }

    private func friendlyModelName(_ model: String) -> String {
        model
            .replacingOccurrences(of: "models/", with: "")
            .replacingOccurrences(of: "gemini-", with: "")
            .split(separator: "-")
            .map { part in
                part.first?.isNumber == true ? String(part) : part.capitalized
            }
            .joined(separator: " ")
    }
}

private struct SystemPromptEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = PlaceholderTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 5, height: 8)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.placeholder = placeholder
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? PlaceholderTextView else { return }
        textView.placeholder = placeholder

        if textView.string != text {
            textView.string = text
        }

        if textView.delegate == nil {
            textView.delegate = context.coordinator
        }

        textView.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

private final class PlaceholderTextView: NSTextView {
    var placeholder: String = "" {
        didSet {
            needsDisplay = true
        }
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, !placeholder.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.placeholderTextColor
        ]

        let point = NSPoint(x: textContainerInset.width, y: textContainerInset.height)
        (placeholder as NSString).draw(at: point, withAttributes: attributes)
    }
}
