import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ChatViewModel

    @State private var selectedSidebarChatID: UUID?
    @State private var sidebarSearchText = ""
    @State private var isSendButtonHovered = false
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            if hasAPIKey, viewModel.availableModels.isEmpty {
                await viewModel.loadAvailableModels(autoSelect: true)
            }
        }
        .onAppear {
            selectedSidebarChatID = viewModel.currentChatID
        }
        .onChange(of: viewModel.currentChatID) { _, nextID in
            if selectedSidebarChatID != nextID {
                selectedSidebarChatID = nextID
            }
        }
        .onChange(of: selectedSidebarChatID) { _, nextID in
            guard let nextID, nextID != viewModel.currentChatID else { return }
            viewModel.openChat(id: nextID)
        }
        .onDisappear {
            viewModel.persistAPIKey()
            viewModel.persistHistory()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Button {
                startNewChat()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))

                    Text("New chat")
                        .fontWeight(.semibold)

                    Spacer()

                    Text("⌘N")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(NewChatButtonStyle())
            .disabled(!viewModel.canManageHistory)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            List(selection: $selectedSidebarChatID) {
                ForEach(HistoryBucket.allCases) { bucket in
                    let items = historyItems(in: bucket)

                    if !items.isEmpty {
                        Section(bucket.title) {
                            ForEach(items) { item in
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
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .overlay {
                if filteredChatHistory.isEmpty {
                    ContentUnavailableView(
                        searchQuery.isEmpty ? "No conversations yet" : "No results",
                        systemImage: searchQuery.isEmpty ? "bubble.left" : "magnifyingglass",
                        description: Text(
                            searchQuery.isEmpty
                                ? "Start a new chat to see it here."
                                : "Try a different title or phrase."
                        )
                    )
                    .controlSize(.small)
                }
            }
            .disabled(!viewModel.canManageHistory)

            Divider()

            SettingsLink {
                HStack(spacing: 9) {
                    Circle()
                        .fill(viewModel.connectionStatus.tint)
                        .frame(width: 7, height: 7)

                    Text(viewModel.connectionStatus.compactTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Settings")
            .padding(8)
        }
        .frame(minWidth: 220, idealWidth: AppTheme.sidebarIdealWidth, maxWidth: 320)
        .background(AppTheme.sidebarBackground)
        .navigationTitle("Gemini")
        .navigationSplitViewColumnWidth(
            min: 220,
            ideal: AppTheme.sidebarIdealWidth,
            max: 320
        )
        .searchable(
            text: $sidebarSearchText,
            placement: .sidebar,
            prompt: "Search conversations"
        )
        .onDeleteCommand {
            deleteSelectedSidebarChat()
        }
    }

    private func sidebarHistoryRow(_ item: ChatThreadSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.callout.weight(item.id == viewModel.currentChatID ? .semibold : .medium))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(historyDate(item.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Text(item.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            conversationHeader

            Divider()
                .opacity(0.65)

            messageList
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            composer
        }
        .background(AppTheme.workspaceBackground)
        .onExitCommand {
            if viewModel.isSending {
                viewModel.cancelResponse()
            }
        }
    }

    private var conversationHeader: some View {
        HStack(spacing: 12) {
            GeminiMark(size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(currentChatTitle)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(viewModel.connectionStatus.tint)
                        .frame(width: 6, height: 6)

                    Text(viewModel.connectionStatus.compactTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 16)

            modelMenu
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
        .background(.bar)
    }

    private var modelMenu: some View {
        Menu {
            Picker("Model", selection: $viewModel.model) {
                ForEach(pickerModels, id: \.self) { item in
                    Text(friendlyModelName(item))
                        .tag(item)
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "cpu")
                    .foregroundStyle(AppTheme.accentBlue)

                Text(friendlyModelName(viewModel.model))
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(AppTheme.elevatedSurface, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.quaternary, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(viewModel.isSending || pickerModels.isEmpty)
        .help("Choose Gemini model")
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            Group {
                if viewModel.messages.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(viewModel.messages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                        .frame(maxWidth: AppTheme.conversationMaxWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, 28)
                        .padding(.bottom, 24)
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

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 0) {
                GeminiMark(size: 58)
                    .padding(.bottom, 20)

                Text(emptyStateTitle)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(emptyStateSubtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                    .padding(.top, 8)

                if hasAPIKey {
                    promptSuggestionGrid
                        .padding(.top, 28)
                } else {
                    setupCard
                        .padding(.top, 28)
                }

                if shouldShowCheckConnectionAction {
                    Button {
                        Task {
                            await viewModel.loadAvailableModels(autoSelect: true)
                        }
                    } label: {
                        Label("Check connection", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoadingModels)
                    .padding(.top, 16)
                }
            }
            .frame(maxWidth: 660)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 72)
            .padding(.bottom, 40)
        }
    }

    private var promptSuggestionGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            ForEach(promptSuggestions, id: \.prompt) { suggestion in
                Button {
                    viewModel.draft = suggestion.prompt
                    isComposerFocused = true
                } label: {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: suggestion.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.accentGradient)
                            .frame(width: 22, height: 22)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(suggestion.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(suggestion.prompt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
                    .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(SuggestionButtonStyle())
                .disabled(viewModel.isSending)
            }
        }
    }

    private var setupCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "key.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.accentGradient)
                .frame(width: 34, height: 34)
                .background(AppTheme.accentBlue.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Connect your Gemini account")
                    .font(.callout.weight(.semibold))
                Text("Add an API key once, then start chatting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            SettingsLink {
                Text("Open Settings")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(maxWidth: 560)
        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let notice = viewModel.errorMessage {
                Label(notice, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: AppTheme.composerMaxWidth, alignment: .leading)
                    .padding(.horizontal, 2)
                    .textSelection(.enabled)
            }

            VStack(spacing: 8) {
                TextField(composerPlaceholder, text: $viewModel.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...7)
                    .focused($isComposerFocused)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Message")

                HStack(spacing: 10) {
                    if !viewModel.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label("Instructions active", systemImage: "text.bubble")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("⌘↩ to send")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button {
                        if viewModel.isSending {
                            viewModel.cancelResponse()
                        } else {
                            viewModel.startSend()
                        }
                    } label: {
                        Image(systemName: viewModel.isSending ? "stop.fill" : "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 32, height: 32)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(
                        ComposerActionButtonStyle(
                            isHovered: isSendButtonHovered,
                            isSending: viewModel.isSending,
                            isEnabled: viewModel.isSending || viewModel.canSend
                        )
                    )
                    .disabled(!viewModel.isSending && !viewModel.canSend)
                    .onHover { isSendButtonHovered = $0 }
                    .help(viewModel.isSending ? "Stop generating (Escape)" : "Send message (Command-Return)")
                    .accessibilityLabel(viewModel.isSending ? "Stop generating" : "Send message")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(isComposerFocused ? AppTheme.accentBlue.opacity(0.48) : Color.secondary.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 16, y: 6)

            Button("Send message") {
                viewModel.startSend()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
            .disabled(!viewModel.canSend)
        }
        .frame(maxWidth: AppTheme.composerMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [AppTheme.workspaceBackground.opacity(0), AppTheme.workspaceBackground],
                startPoint: .top,
                endPoint: .center
            )
        )
    }

    private var pickerModels: [String] {
        viewModel.availableModels.isEmpty ? [viewModel.model] : viewModel.availableModels
    }

    private var filteredChatHistory: [ChatThreadSummary] {
        guard !searchQuery.isEmpty else { return viewModel.chatHistory }

        return viewModel.chatHistory.filter { item in
            item.title.localizedCaseInsensitiveContains(searchQuery)
                || item.preview.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private var searchQuery: String {
        sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasAPIKey: Bool {
        !viewModel.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentChatTitle: String {
        if let firstUserMessage = viewModel.messages.first(where: { $0.role == .user }) {
            let compact = firstUserMessage.text
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            let title = String(compact.prefix(64))
            if !title.isEmpty {
                return title
            }
        }

        return viewModel.chatHistory
            .first(where: { $0.id == viewModel.currentChatID })?
            .title ?? "New conversation"
    }

    private var emptyStateTitle: String {
        hasAPIKey ? "What can I help you explore?" : "Welcome to Gemini for Mac"
    }

    private var emptyStateSubtitle: String {
        switch viewModel.connectionStatus {
        case .notConfigured:
            return "A focused, private workspace for your conversations with Gemini."
        case .notChecked:
            return "Your key is ready. Choose a starting point or write your own message below."
        case .checking:
            return "Connecting to Gemini and loading the models available to your key…"
        case .connected:
            return "Start with an idea below, or ask anything in the message field."
        case .failed:
            return "You can still compose a message, or check the connection before you begin."
        }
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
        hasAPIKey ? "Message Gemini…" : "Add an API key in Settings to begin"
    }

    private var promptSuggestions: [(title: String, prompt: String, icon: String)] {
        [
            ("Make a plan", "Help me turn a rough idea into a clear action plan", "checklist"),
            ("Write with me", "Draft a thoughtful message from a few bullet points", "pencil.line"),
            ("Understand something", "Explain a complex topic in simple, practical terms", "lightbulb"),
            ("Think it through", "Challenge my assumptions and help me compare my options", "arrow.triangle.branch")
        ]
    }

    private func historyItems(in bucket: HistoryBucket) -> [ChatThreadSummary] {
        filteredChatHistory.filter { bucket.contains($0.updatedAt) }
    }

    private func historyDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }

        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        }

        return date.formatted(.dateTime.month(.abbreviated).day())
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

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastID = viewModel.messages.last?.id else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    private func startNewChat() {
        viewModel.startNewChat()
        selectedSidebarChatID = viewModel.currentChatID
        isComposerFocused = true
    }

    private func deleteSelectedSidebarChat() {
        guard viewModel.canManageHistory, let selectedSidebarChatID else { return }
        viewModel.deleteChat(id: selectedSidebarChatID)
        self.selectedSidebarChatID = viewModel.currentChatID
    }
}

private enum HistoryBucket: CaseIterable, Identifiable {
    case today
    case yesterday
    case previousSevenDays
    case older

    var id: Self { self }

    var title: String {
        switch self {
        case .today:
            return "Today"
        case .yesterday:
            return "Yesterday"
        case .previousSevenDays:
            return "Previous 7 Days"
        case .older:
            return "Older"
        }
    }

    func contains(_ date: Date) -> Bool {
        let calendar = Calendar.current

        switch self {
        case .today:
            return calendar.isDateInToday(date)
        case .yesterday:
            return calendar.isDateInYesterday(date)
        case .previousSevenDays:
            guard !calendar.isDateInToday(date), !calendar.isDateInYesterday(date) else { return false }
            let cutoff = calendar.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
            return date >= cutoff
        case .older:
            let cutoff = calendar.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
            return date < cutoff
        }
    }
}

private struct GeminiMark: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(AppTheme.accentGradient, in: RoundedRectangle(cornerRadius: size * 0.31, style: .continuous))
            .shadow(color: AppTheme.accentViolet.opacity(0.18), radius: size * 0.22, y: size * 0.08)
            .accessibilityHidden(true)
    }
}

private struct NewChatButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .background(
                AppTheme.elevatedSurface.opacity(configuration.isPressed ? 0.7 : 1),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
    }
}

private struct SuggestionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ComposerActionButtonStyle: ButtonStyle {
    let isHovered: Bool
    let isSending: Bool
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.7))
            .background {
                Circle()
                    .fill(
                        isSending
                            ? AnyShapeStyle(Color.orange.opacity(isHovered ? 1 : 0.88))
                            : AnyShapeStyle(AppTheme.accentGradient.opacity(isEnabled ? (isHovered ? 1 : 0.9) : 0.38))
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.92 : (isHovered ? 1.04 : 1))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
