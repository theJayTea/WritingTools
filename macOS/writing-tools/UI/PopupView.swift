import SwiftUI
import ApplicationServices

struct PopupView: View {
    @ObservedObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    let closeAction: () -> Void

    @State private var customText: String = ""

    var body: some View {
        VStack(spacing: 16) {
            // Close button
            HStack {
                Spacer()
                Button(action: closeAction) {
                    Image(systemName: "xmark.circle.fill")
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
                    appState.selectedText.isEmpty ? "Please enter an instruction..." : "Describe your change...",
                    text: $customText
                )
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onSubmit {
                    processCustomChange()
                }

                Button(action: processCustomChange) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(customText.isEmpty)
            }
            .padding(.horizontal)

            if !appState.selectedText.isEmpty {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(WritingOption.allCases) { option in
                        OptionButton(option: option) {
                            processOption(option)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.windowBackgroundColor).opacity(0.95) : Color.white.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
    }

    private func processCustomChange() {
        guard !customText.isEmpty else { return }
        processCustomInstruction(customText)
    }

    private func processOption(_ option: WritingOption) {
        appState.isProcessing = true

        Task {
            do {
                let prompt = "\(option.systemPrompt):\n\n\(appState.selectedText)"

                let result = try await appState.geminiProvider.processText(userPrompt: prompt)

                if [.summary, .keyPoints, .table].contains(option) {
                    await MainActor.run {
                        showResponseWindow(for: option, with: result)
                    }
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)

                    closeAction()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        simulatePaste()
                    }
                }
            } catch {
                print("Error processing text: \(error.localizedDescription)")
            }

            appState.isProcessing = false
        }
    }

    private func processCustomInstruction(_ instruction: String) {
        guard !instruction.isEmpty else { return }
        appState.isProcessing = true

        Task {
            do {
                let prompt = """
                You are a writing and coding assistant. Your sole task is to apply the user's specified changes to the provided text.
                Output ONLY the modified text without any comments, explanations, or analysis.
                Do not include additional suggestions or formatting in your response.

                User's instruction: \(instruction)

                Text:
                \(appState.selectedText)
                """

                let result = try await appState.geminiProvider.processText(userPrompt: prompt)

                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result, forType: .string)

                closeAction()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    simulatePaste()
                }
            } catch {
                print("Error processing text: \(error.localizedDescription)")
            }

            appState.isProcessing = false
        }
    }

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
        .buttonStyle(.plain)
    }
}
