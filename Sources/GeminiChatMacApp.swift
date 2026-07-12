import SwiftUI

@main
struct GeminiChatMacApp: App {
    @StateObject private var viewModel = ChatViewModel()

    var body: some Scene {
        Window("Gemini", id: "main") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 760, minHeight: 600)
        }
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    viewModel.startNewChat()
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(!viewModel.canManageHistory)
            }
        }

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
