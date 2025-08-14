import SwiftUI
import ApplicationServices

final class PopupViewModel: ObservableObject {
  @Published var isEditMode: Bool = false
}

struct PopupView: View {
  @ObservedObject var appState: AppState
  @ObservedObject var viewModel: PopupViewModel
  @Environment(\.colorScheme) var colorScheme
  @AppStorage("use_gradient_theme") private var useGradientTheme = false

  @State private var customText: String = ""
  @State private var isCustomLoading: Bool = false
  @State private var processingCommandId: UUID? = nil

  @State private var showingCommandsView = false
  @State private var editingCommand: CommandModel? = nil

  let closeAction: () -> Void

  // Grid layout for two columns
  private let columns = [
    GridItem(.flexible(), spacing: 8),
    GridItem(.flexible(), spacing: 8),
  ]

  var body: some View {
    VStack(spacing: 16) {
      // Top bar with buttons
      HStack {
        Button(action: {
          if viewModel.isEditMode {
            viewModel.isEditMode = false
          } else {
            closeAction()
          }
        }) {
          Image(systemName: "xmark")
            .font(.body)
            .foregroundColor(.secondary)
            .frame(width: 28, height: 28)
            .background(Color(.controlBackgroundColor))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(viewModel.isEditMode ? "Exit Edit Mode" : "Close")
        .padding(.top, 8)
        .padding(.leading, 8)

        Spacer()

        Button(action: {
          viewModel.isEditMode.toggle()
          // Optional: keep notification if other parts listen to it
          NotificationCenter.default.post(
            name: NSNotification.Name("EditModeChanged"),
            object: nil
          )
        }) {
          Image(
            systemName: viewModel.isEditMode ? "checkmark" : "square.and.pencil"
          )
          .font(.body)
          .foregroundColor(.secondary)
          .frame(width: 28, height: 28)
          .background(Color(.controlBackgroundColor))
          .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(viewModel.isEditMode ? "Save Changes" : "Edit Commands")
        .padding(.top, 8)
        .padding(.trailing, 8)
      }

      // Custom input with send button
      if !viewModel.isEditMode {
        HStack(spacing: 8) {
          TextField(
            appState.selectedText.isEmpty
              ? "Describe your change..."
              : "Describe your change...",
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
      }

      if !appState.selectedText.isEmpty || !appState.selectedImages.isEmpty {
        // Command buttons grid
        ScrollView {
          LazyVGrid(columns: columns, spacing: 8) {
            ForEach(appState.commandManager.commands) { command in
              CommandButton(
                command: command,
                isEditing: viewModel.isEditMode,
                isLoading: processingCommandId == command.id,
                onTap: {
                  processingCommandId = command.id
                  Task {
                    await processCommandAndCloseWhenDone(command)
                  }
                },
                onEdit: {
                  editingCommand = command
                  showingCommandsView = true
                },
                onDelete: {
                  print("Deleting command: \(command.name)")
                  appState.commandManager.deleteCommand(command)
                  NotificationCenter.default.post(
                    name: NSNotification.Name("CommandsChanged"),
                    object: nil
                  )
                }
              )
            }
          }
          .padding(.horizontal, 8)
        }
        .padding(.horizontal, 8)
      }

      if viewModel.isEditMode {
        Button(action: { showingCommandsView = true }) {
          HStack {
            Image(systemName: "plus.circle.fill")
            Text("Manage Commands")
          }
          .frame(maxWidth: .infinity)
          .padding()
          .background(Color(.controlBackgroundColor))
          .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
      }
    }
    .padding(.bottom, 8)
    .windowBackground(useGradient: useGradientTheme)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
    .sheet(isPresented: $showingCommandsView) {
      CommandsView(commandManager: appState.commandManager)
        .onDisappear {
          NotificationCenter.default.post(
            name: NSNotification.Name("CommandsChanged"),
            object: nil
          )
        }
    }
  }

  // Process a command asynchronously and only close the popup when done
  private func processCommandAndCloseWhenDone(
    _ command: CommandModel
  ) async {
    guard !appState.selectedText.isEmpty else {
      processingCommandId = nil
      return
    }

    appState.isProcessing = true

    do {
      let systemPrompt = command.prompt
      let userText = appState.selectedText

      let result = try await appState.activeProvider.processText(
        systemPrompt: systemPrompt,
        userPrompt: userText,
        images: appState.selectedImages,
        streaming: false
      )

      await MainActor.run {
        if command.useResponseWindow {
          let window = ResponseWindow(
            title: command.name,
            content: result,
            selectedText: userText,
            option: .proofread
          )

          WindowManager.shared.addResponseWindow(window)
          window.makeKeyAndOrderFront(nil)
          window.orderFrontRegardless()
        } else {
          if command.preserveFormatting {
            appState.replaceSelectedTextPreservingAttributes(with: result)
          } else {
            appState.replaceSelectedText(with: result)
          }
        }

        closeAction()
        processingCommandId = nil
      }
    } catch {
      print("Error processing command: \(error.localizedDescription)")
      await MainActor.run {
        processingCommandId = nil
      }
    }

    await MainActor.run {
      appState.isProcessing = false
    }
  }

  private func processCustomChange() {
    guard !customText.isEmpty else { return }
    isCustomLoading = true
    processCustomInstruction(customText)
  }

  private func processCustomInstruction(_ instruction: String) {
    guard !instruction.isEmpty else { return }
    appState.isProcessing = true

    Task {
      do {
        let systemPrompt = """
        You are a writing and coding assistant. Your sole task is to respond \
        to the user's instruction thoughtfully and comprehensively.
        If the instruction is a question, provide a detailed answer. But \
        always return the best and most accurate answer and not different \
        options. 
        If it's a request for help, provide clear guidance and examples where \
        appropriate. Make sure tu use the language used or specified by the \
        user instruction.
        Use Markdown formatting to make your response more readable.
        """

        let userPrompt = appState.selectedText.isEmpty
          ? instruction
          : """
            User's instruction: \(instruction)
            
            Text:
            \(appState.selectedText)
            """

        let result = try await appState.activeProvider.processText(
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          images: appState.selectedImages,
          streaming: false
        )

        await MainActor.run {
          let window = ResponseWindow(
            title: "AI Response",
            content: result,
            selectedText: appState.selectedText.isEmpty
              ? instruction : appState.selectedText,
            option: .proofread
          )

          WindowManager.shared.addResponseWindow(window)
          window.makeKeyAndOrderFront(nil)
          window.orderFrontRegardless()

          customText = ""
          isCustomLoading = false
          closeAction()
        }
      } catch {
        print("Error processing text: \(error.localizedDescription)")
        isCustomLoading = false
      }

      appState.isProcessing = false
    }
  }
}
