import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var apiKeySaveTask: Task<Void, Never>?
    @State private var showSettings: Bool = false
    @State private var selectedSidebarChatID: UUID?
    @State private var sidebarSearchText: String = ""
    @State private var revealAPIKey: Bool = false
    @State private var showModelPicker: Bool = false
    @State private var modelMenuPulse: Bool = false
    @State private var modelMenuAnimationTask: Task<Void, Never>?
    @State private var isModelPickerHovered: Bool = false
    @State private var hoveredModelItem: String?
    @State private var isSendButtonHovered: Bool = false
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .task {
            if !viewModel.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, viewModel.availableModels.isEmpty {
                await viewModel.loadAvailableModels(autoSelect: true)
            }
        }
        .onAppear {
            selectedSidebarChatID = viewModel.currentChatID
        }
        .onChange(of: viewModel.apiKey) { _, _ in
            scheduleAPIKeyPersist()
        }
        .onChange(of: viewModel.currentChatID) { _, nextID in
            if selectedSidebarChatID != nextID {
                selectedSidebarChatID = nextID
            }
        }
        .onChange(of: selectedSidebarChatID) { _, nextID in
            guard let nextID else { return }
            guard nextID != viewModel.currentChatID else { return }
            viewModel.openChat(id: nextID)
        }
        .onChange(of: viewModel.model) { _, _ in
            animateModelMenuSelection()
        }
        .onChange(of: showModelPicker) { _, isShown in
            if !isShown {
                hoveredModelItem = nil
            }
        }
        .onDisappear {
            apiKeySaveTask?.cancel()
            modelMenuAnimationTask?.cancel()
            showModelPicker = false
            hoveredModelItem = nil
            viewModel.persistAPIKey()
            viewModel.persistHistory()
        }
    }

    private var sidebar: some View {
        List(selection: $selectedSidebarChatID) {
            ForEach(filteredChatHistory) { item in
                sidebarHistoryRow(item)
                    .tag(item.id)
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.deleteChat(id: item.id)
                            selectedSidebarChatID = viewModel.currentChatID
                        } label: {
                            Label("Delete Chat", systemImage: "trash")
                        }
                        .disabled(!viewModel.canManageHistory)
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Chats")
        .searchable(text: $sidebarSearchText, placement: .sidebar, prompt: "Search chats")
        .overlay {
            if filteredChatHistory.isEmpty {
                ContentUnavailableView(
                    sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No Chats Yet" : "No Results",
                    systemImage: sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "clock.arrow.circlepath" : "magnifyingglass",
                    description: Text(
                        sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Your chat history will appear here."
                        : "Try a different search query."
                    )
                )
            }
        }
        .disabled(!viewModel.canManageHistory)
        .onDeleteCommand {
            deleteSelectedSidebarChat()
        }
    }

    private func sidebarHistoryRow(_ item: ChatThreadSummary) -> some View {
        let isCurrent = item.id == viewModel.currentChatID

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(item.title)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Text(item.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(historyDate(item.updatedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var filteredChatHistory: [ChatThreadSummary] {
        let query = sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.chatHistory }

        return viewModel.chatHistory.filter { item in
            item.title.localizedCaseInsensitiveContains(query)
                || item.preview.localizedCaseInsensitiveContains(query)
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            composer
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.clearChat()
                    selectedSidebarChatID = viewModel.currentChatID
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(!viewModel.canManageHistory)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
    }

    private var pickerModels: [String] {
        if viewModel.availableModels.isEmpty {
            return [viewModel.model]
        }
        return viewModel.availableModels
    }

    private var modelMenu: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                showModelPicker.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Text(modelMenuLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(showModelPicker ? 180 : 0))
                    .animation(.spring(response: 0.24, dampingFraction: 0.82), value: showModelPicker)
            }
            .frame(width: 220, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(showModelPicker ? Color.accentColor.opacity(0.18) : (isModelPickerHovered ? Color.accentColor.opacity(0.12) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(showModelPicker ? Color.accentColor.opacity(0.7) : (isModelPickerHovered ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.22)), lineWidth: 1)
            )
            .scaleEffect(modelMenuPulse ? 1.03 : (isModelPickerHovered ? 1.01 : 1.0))
            .animation(.spring(response: 0.26, dampingFraction: 0.66), value: modelMenuPulse)
            .animation(.easeOut(duration: 0.16), value: isModelPickerHovered)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: showModelPicker)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isModelPickerHovered = hovering
            }
        }
        .disabled(viewModel.isSending || pickerModels.isEmpty)
        .popover(isPresented: $showModelPicker, arrowEdge: .top) {
            modelPickerPopover
        }
    }

    private var modelPickerPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select model")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(pickerModels, id: \.self) { item in
                        modelPickerRow(item)
                    }
                }
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipped()
        }
        .padding(12)
        .frame(width: 320, height: modelPickerPopoverHeight)
    }

    private var modelPickerPopoverHeight: CGFloat {
        let base = CGFloat(pickerModels.count) * 34 + 48
        return min(max(base, 120), 320)
    }

    private func modelPickerRow(_ item: String) -> some View {
        let isSelected = item == viewModel.model
        let isHovered = hoveredModelItem == item

        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                viewModel.model = item
                showModelPicker = false
            }
        } label: {
            HStack(spacing: 8) {
                Text(item)
                    .fontWeight(isHovered || isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : (isHovered ? Color.accentColor.opacity(0.10) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isHovered ? Color.accentColor.opacity(0.38) : Color.clear, lineWidth: 1)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .animation(.easeOut(duration: 0.14), value: isSelected)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                if hovering {
                    hoveredModelItem = item
                } else if hoveredModelItem == item {
                    hoveredModelItem = nil
                }
            }
        }
    }

    private var modelMenuLabel: String {
        let value = viewModel.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Select model" : value
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            Group {
                if viewModel.messages.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)

                        Text("New Chat")
                            .font(.title3.weight(.semibold))

                        Text(emptyStateSubtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)

                        HStack(spacing: 8) {
                            if shouldShowOpenSettingsAction {
                                Button("Open Settings") {
                                    showSettings = true
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            if shouldShowCheckConnectionAction {
                                Button("Check Connection") {
                                    Task {
                                        await viewModel.loadAvailableModels(autoSelect: true)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isLoadingModels)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.messages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.messages.last?.text ?? "") { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastID = viewModel.messages.last?.id else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            VStack(spacing: 12) {
                TextField(composerPlaceholder, text: $viewModel.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1 ... 8)
                    .focused($isComposerFocused)
                    .onSubmit {
                        viewModel.startSend()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    modelMenu

                    Spacer()

                    Button {
                        if viewModel.isSending {
                            viewModel.cancelResponse()
                        } else {
                            viewModel.startSend()
                        }
                    } label: {
                        ZStack {
                            if viewModel.isSending {
                                Image(systemName: "stop.fill")
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Image(systemName: "arrow.up")
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: viewModel.isSending)
                    }
                    .buttonStyle(
                        ComposerActionButtonStyle(
                            isHovered: isSendButtonHovered,
                            isSending: viewModel.isSending,
                            isEnabled: viewModel.isSending ? true : viewModel.canSend
                        )
                    )
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(viewModel.isSending ? false : !viewModel.canSend)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.16)) {
                            isSendButtonHovered = hovering
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            )
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 8) {
                Label(connectionStatusCompactTitle, systemImage: connectionStatusIcon)
                    .font(.caption2)
                    .foregroundStyle(connectionStatusColor)

                Text("•")
                    .foregroundStyle(.tertiary)

                Text("Return to send • Command+Return for new line")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.draft.append("\n")
            } label: {
                EmptyView()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
            .disabled(!isComposerFocused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var settingsSheet: some View {
        let hasAPIKey = !viewModel.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSystemPrompt = !viewModel.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return NavigationStack {
            Form {
                Section {
                    if revealAPIKey {
                        TextField("Paste Gemini API key", text: $viewModel.apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Paste Gemini API key", text: $viewModel.apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Show API key", isOn: $revealAPIKey)

                    ControlGroup {
                        Button("Save Key") {
                            viewModel.saveAPIKey()
                            if hasAPIKey {
                                Task {
                                    await viewModel.loadAvailableModels(autoSelect: true)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Remove Key", role: .destructive) {
                            viewModel.apiKey = ""
                            viewModel.saveAPIKey()
                        }
                        .disabled(!hasAPIKey)
                    }
                } header: {
                    Text("API Key")
                } footer: {
                    Text("Stored locally on this Mac.")
                }

                Section {
                    LabeledContent("Saved key") {
                        Text(hasAPIKey ? "Configured" : "Not set")
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Status") {
                        Label(connectionStatusTitle, systemImage: connectionStatusIcon)
                            .foregroundStyle(connectionStatusColor)
                    }

                    LabeledContent("Loaded models") {
                        if viewModel.isLoadingModels {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading…")
                            }
                            .foregroundStyle(.secondary)
                        } else {
                            let count = viewModel.availableModels.count
                            Text(count == 0 ? "Not loaded" : "\(count)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if case .failed(let message) = viewModel.connectionStatus {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        Button("Check Connection") {
                            Task {
                                await viewModel.loadAvailableModels(autoSelect: true)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isLoadingModels || !hasAPIKey)

                        if viewModel.isLoadingModels {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Use Check Connection to refresh available models for your key.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        SystemPromptEditor(
                            text: $viewModel.systemPrompt,
                            placeholder: "Describe the behavior you want from the assistant…"
                        )
                        .frame(height: 130)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )

                        HStack {
                            Text("\(viewModel.systemPrompt.count) characters")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)

                            Spacer()

                            if hasSystemPrompt {
                                Button("Clear Prompt") {
                                    viewModel.systemPrompt = ""
                                }
                            }
                        }
                    }
                } header: {
                    Text("System Prompt")
                } footer: {
                    Text("Applied to all new model responses.")
                }

                Section {
                    Picker("Safety level", selection: $viewModel.safetyPreset) {
                        ForEach(GeminiSafetyPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(viewModel.safetyPreset.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Core harms are always enforced by Gemini.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Safety & Censorship")
                }

                if let errorMessage = viewModel.errorMessage {
                    Section("Error") {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showSettings = false
                    }
                }
            }
            .task {
                if hasAPIKey && viewModel.availableModels.isEmpty {
                    await viewModel.loadAvailableModels(autoSelect: true)
                }
            }
            .onDisappear {
                revealAPIKey = false
            }
        }
        .frame(minWidth: 560, minHeight: 500)
    }

    private var connectionStatusTitle: String {
        switch viewModel.connectionStatus {
        case .notConfigured:
            return "Not configured"
        case .notChecked:
            return "Not checked"
        case .checking:
            return "Checking…"
        case .connected(let modelsCount):
            return "Connected (\(modelsCount) models)"
        case .failed:
            return "Connection failed"
        }
    }

    private var connectionStatusIcon: String {
        switch viewModel.connectionStatus {
        case .connected:
            return "checkmark.circle.fill"
        case .checking:
            return "arrow.triangle.2.circlepath.circle"
        case .failed:
            return "xmark.circle.fill"
        case .notConfigured, .notChecked:
            return "exclamationmark.circle"
        }
    }

    private var connectionStatusColor: Color {
        switch viewModel.connectionStatus {
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

    private var connectionStatusCompactTitle: String {
        switch viewModel.connectionStatus {
        case .notConfigured:
            return "No API key"
        case .notChecked:
            return "Not checked"
        case .checking:
            return "Checking"
        case .connected:
            return "Connected"
        case .failed:
            return "Failed"
        }
    }

    private var emptyStateSubtitle: String {
        switch viewModel.connectionStatus {
        case .notConfigured:
            return "Add your Gemini API key in Settings to start chatting."
        case .notChecked:
            return "Check connection and start your first chat with Gemini."
        case .checking:
            return "Checking Gemini connection…"
        case .connected:
            return "Ask your first question below to start chatting with Gemini."
        case .failed:
            return "Could not connect to Gemini. Check key or model availability."
        }
    }

    private var shouldShowOpenSettingsAction: Bool {
        if case .notConfigured = viewModel.connectionStatus {
            return true
        }
        return false
    }

    private var shouldShowCheckConnectionAction: Bool {
        switch viewModel.connectionStatus {
        case .notChecked, .failed:
            return true
        case .notConfigured, .checking, .connected:
            return false
        }
    }

    private var composerPlaceholder: String {
        switch viewModel.connectionStatus {
        case .notConfigured:
            return "Add API key in Settings to start"
        case .checking:
            return "Checking connection..."
        case .failed:
            return "Connection failed. Check settings and try again"
        case .notChecked, .connected:
            return "Ask anything"
        }
    }

    private func historyDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func deleteSelectedSidebarChat() {
        guard viewModel.canManageHistory else { return }
        guard let selectedSidebarChatID else { return }
        viewModel.deleteChat(id: selectedSidebarChatID)
        self.selectedSidebarChatID = viewModel.currentChatID
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

    private func animateModelMenuSelection() {
        modelMenuAnimationTask?.cancel()
        modelMenuAnimationTask = Task {
            await MainActor.run {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.62)) {
                    modelMenuPulse = true
                }
            }

            try? await Task.sleep(nanoseconds: 170_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                    modelMenuPulse = false
                }
            }
        }
    }

    private struct ComposerActionButtonStyle: ButtonStyle {
        let isHovered: Bool
        let isSending: Bool
        let isEnabled: Bool

        func makeBody(configuration: Configuration) -> some View {
            let baseColor: Color = isSending ? .orange : .accentColor
            let fillOpacity: Double = isEnabled ? (isHovered ? 0.95 : 0.82) : 0.35
            let borderOpacity: Double = isHovered ? 0.38 : 0.2

            return configuration.label
                .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.65))
                .background(
                    Circle()
                        .fill(baseColor.opacity(fillOpacity))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.92 : (isHovered ? 1.06 : (isSending ? 1.03 : 1.0)))
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isHovered)
                .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isSending)
        }
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

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.placeholderTextColor
        ]

        let point = NSPoint(
            x: textContainerInset.width,
            y: textContainerInset.height
        )

        (placeholder as NSString).draw(at: point, withAttributes: attrs)
    }
}
