import SwiftUI
import ApplicationServices

struct PopupView: View {
    @ObservedObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var commandsManager = CustomCommandsManager()
    let closeAction: () -> Void
    @AppStorage("use_gradient_theme") private var useGradientTheme = false
    @State private var customText: String = ""
    @State private var loadingOptions: Set<String> = []
    @State private var isCustomLoading: Bool = false
    @State private var showingCustomCommands = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Top bar with close and add buttons
            HStack {
                
                Button(action: closeAction) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.leading, 8)
                
                Spacer()
                
                Button(action: { showingCustomCommands = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.trailing, 8)
            }
            
            // Custom input with send button
            HStack(spacing: 8) {
                TextField(
                    appState.selectedText.isEmpty ? "Describe your change..." : "Describe your change...",
                    text: $customText
                )
                .textFieldStyle(.plain)
                .appleStyleTextField(
                    text: customText,
                    isLoading: isCustomLoading,
                    onSubmit: processCustomChange
                )
            }
            .padding(.horizontal)
            
            if !appState.selectedText.isEmpty || !appState.selectedImages.isEmpty {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        // Built-in options
                        ForEach(WritingOption.allCases) { option in
                            OptionButton(
                                option: option,
                                action: { processOption(option) },
                                isLoading: loadingOptions.contains(option.id)
                            )
                        }
                        
                        // Custom commands
                        ForEach(commandsManager.commands) { command in
                            CustomOptionButton(
                                command: command,
                                action: { processCustomCommand(command) },
                                isLoading: loadingOptions.contains(command.id.uuidString)
                            )
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 16)
        .windowBackground(useGradient: useGradientTheme)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
        .sheet(isPresented: $showingCustomCommands) {
            CustomCommandsView(commandsManager: commandsManager)
        }
    }
    
    // Process custom commands
    private func processCustomCommand(_ command: CustomCommand) {
        loadingOptions.insert(command.id.uuidString)
        appState.isProcessing = true
        
        Task {
            defer {
                loadingOptions.remove(command.id.uuidString)
                appState.isProcessing = false
            }
            
            do {
                let result = try await appState.activeProvider.processText(
                    systemPrompt: command.prompt,
                    userPrompt: appState.selectedText,
                    images: appState.selectedImages
                )
                
                if command.useResponseWindow {
                    // Show response in a new window
                    await MainActor.run {
                        let window = ResponseWindow(
                            title: command.name,
                            content: result,
                            selectedText: appState.selectedText,
                            option: .proofread // Using proofread as default since this is a custom command
                        )
                        
                        WindowManager.shared.addResponseWindow(window)
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                    }
                } else {
                    // Set clipboard content and paste in one go
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                    
                    // Wait briefly then paste once
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        simulatePaste()
                    }
                }
                
                closeAction()
            } catch {
                print("Error processing custom command: \(error.localizedDescription)")
            }
        }
    }
    
    
    // Process custom text changes
    private func processCustomChange() {
        guard !customText.isEmpty else { return }
        isCustomLoading = true
        processCustomInstruction(customText)
    }
    
    // Process predefined writing options
    private func processOption(_ option: WritingOption) {
        loadingOptions.insert(option.id)
        appState.isProcessing = true
        
        Task {
            defer {
                loadingOptions.remove(option.id)
                appState.isProcessing = false
            }
            do {
                let result = try await appState.activeProvider.processText(
                    systemPrompt: option.systemPrompt,
                    userPrompt: appState.selectedText,
                    images: appState.selectedImages
                )
                
                if [.summary, .keyPoints, .table].contains(option) {
                    await MainActor.run {
                        showResponseWindow(for: option, with: result)
                    }
                    // Close the popup window after showing the response window
                    closeAction()
                } else {
                    // Set clipboard content and paste in one go
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                    
                    closeAction()
                    
                    // Reactivate previous application and paste
                    if let previousApp = appState.previousApplication {
                        previousApp.activate()
                        
                        // Wait briefly for activation then paste once
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            simulatePaste()
                        }
                    }
                }
            } catch {
                print("Error processing text: \(error.localizedDescription)")
            }
            
            appState.isProcessing = false
        }
    }
    
    // Process custom instructions
    private func processCustomInstruction(_ instruction: String) {
        guard !instruction.isEmpty else { return }
        appState.isProcessing = true
        
        Task {
            do {
                let systemPrompt = """
                You are a writing and coding assistant. Your sole task is to respond to the user's instruction thoughtfully and comprehensively.
                If the instruction is a question, provide a detailed answer. But always return the best and most accurate answer and not different options. 
                If it's a request for help, provide clear guidance and examples where appropriate. Make sure tu use the language used or specified by the user instruction.
                Use Markdown formatting to make your response more readable.
                """
                
                let userPrompt = appState.selectedText.isEmpty ?
                instruction :
                    """
                    User's instruction: \(instruction)
                    
                    Text:
                    \(appState.selectedText)
                    """
                
                let result = try await appState.activeProvider.processText(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    images: appState.selectedImages
                )
                
                // Always show response in a new window
                await MainActor.run {
                    let window = ResponseWindow(
                        title: "AI Response",
                        content: result,
                        selectedText: appState.selectedText.isEmpty ? instruction : appState.selectedText,
                        option: .proofread // Using proofread as default, the response window will adapt based on content
                    )
                    
                    WindowManager.shared.addResponseWindow(window)
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
                
                closeAction()
            } catch {
                print("Error processing text: \(error.localizedDescription)")
            }
            
            isCustomLoading = false
            appState.isProcessing = false
        }
    }
    
    // Show response window for certain options
    private func showResponseWindow(for option: WritingOption, with result: String) {
        DispatchQueue.main.async {
            let window = ResponseWindow(
                title: "\(option.rawValue) Result",
                content: result,
                selectedText: appState.selectedText,
                option: option
            )
            
            // Store a reference to prevent deallocation
            WindowManager.shared.addResponseWindow(window)
            
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
    
    // Simulate paste command
    private func simulatePaste() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        
        // Create a Command + V key down event
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        
        // Create a Command + V key up event
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        
        // Post the events to the HID event system
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

struct OptionButton: View {
    let option: WritingOption
    let action: () -> Void
    let isLoading: Bool
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: option.icon)
                Text(option.rawValue)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(LoadingButtonStyle(isLoading: isLoading))
        .disabled(isLoading)
    }
}

struct CustomOptionButton: View {
    let command: CustomCommand
    let action: () -> Void
    let isLoading: Bool
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: command.icon)
                Text(command.name)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(LoadingButtonStyle(isLoading: isLoading))
        .disabled(isLoading)
    }
}
