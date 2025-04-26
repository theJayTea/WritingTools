import SwiftUI
import KeyboardShortcuts

struct CommandEditor: View {
    @Binding var command: CommandModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) var colorScheme
    
    var onSave: () -> Void
    var onCancel: () -> Void
    var isBuiltIn: Bool
    
    @State private var name: String
    @State private var prompt: String
    @State private var selectedIcon: String
    @State private var useResponseWindow: Bool
    @State private var hasShortcut: Bool
    @State private var showingIconPicker = false
    @State private var isNameDuplicate = false
    @State private var showDuplicateAlert = false
    
    init(command: Binding<CommandModel>, onSave: @escaping () -> Void, onCancel: @escaping () -> Void, commandManager: CommandManager? = nil) {
        self._command = command
        self.onSave = onSave
        self.onCancel = onCancel
        self.isBuiltIn = command.wrappedValue.isBuiltIn
        
        _name = State(initialValue: command.wrappedValue.name)
        _prompt = State(initialValue: command.wrappedValue.prompt)
        _selectedIcon = State(initialValue: command.wrappedValue.icon)
        _useResponseWindow = State(initialValue: command.wrappedValue.useResponseWindow)
        _hasShortcut = State(initialValue: command.wrappedValue.hasShortcut)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Enhanced Header
            HStack {
                Text(isBuiltIn ? "Edit Built-In Command" : "Edit Command")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: { onCancel() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Cancel")
            }
            .padding()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Command Information Card
                    VStack(alignment: .leading, spacing: 20) {
                        // Name & Icon with better spacing and styling
                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Name")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                TextField("Command Name", text: $name)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(maxWidth: .infinity)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Icon")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Button(action: { showingIconPicker = true }) {
                                    HStack {
                                        Image(systemName: selectedIcon)
                                            .font(.title2)
                                            .frame(width: 30)
                                        
                                        Text("Change Icon")
                                            .font(.subheadline)
                                    }
                                    .padding(8)
                                    .background(Color(.controlBackgroundColor))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Display response in window toggle
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Display response in window", isOn: $useResponseWindow)
                                .padding(.horizontal)
                        }
                        
                        // Keyboard Shortcut
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Keyboard Shortcut")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.horizontal)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Enable keyboard shortcut for this command", isOn: $hasShortcut)
                                    .padding(.horizontal)
                                
                                if hasShortcut {
                                    HStack {
                                        Text("Command shortcut:")
                                            .foregroundColor(.secondary)
                                        
                                        KeyboardShortcuts.Recorder(
                                            for: .commandShortcut(for: command.id),
                                            onChange: { shortcut in
                                                // Ensure hasShortcut stays true if a shortcut is set
                                                if shortcut != nil {
                                                    hasShortcut = true
                                                }
                                            }
                                        )
                                    }
                                    .padding(.horizontal)
                                    
                                    Text("Tip: This shortcut will execute the command directly without opening the popup window.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        // Prompt
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Prompt")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.textBackgroundColor))
                                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                                    
                                TextEditor(text: $prompt)
                                    .font(.system(.body, design: .monospaced))
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .padding(8)
                            }
                            .frame(height: 200)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .padding(.horizontal)
                        
                        if isBuiltIn {
                            VStack {
                                Text("This is a built-in command. Your changes will be saved but you can reset to the original configuration later if needed.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding()
                            }
                        }
                        
                        // Buttons
                        HStack {
                            Button(action: {
                                onCancel()
                            }) {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: {
                                // If hasShortcut is false but there is a shortcut set, remove it
                                if !hasShortcut {
                                    KeyboardShortcuts.reset(.commandShortcut(for: command.id))
                                }
                                
                                // Save changes back to the command
                                var updatedCommand = command
                                updatedCommand.name = name
                                updatedCommand.prompt = prompt
                                updatedCommand.icon = selectedIcon
                                updatedCommand.useResponseWindow = useResponseWindow
                                updatedCommand.hasShortcut = hasShortcut
                                
                                // Update the binding
                                command = updatedCommand
                                
                                // Post notification that commands have changed to update shortcuts
                                NotificationCenter.default.post(name: NSNotification.Name("CommandsChanged"), object: nil)
                                
                                // Call the save action
                                onSave()
                            }) {
                                Text("Save")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding()
                    }
                }
                .padding(.vertical)
            }
        }
        .frame(width: 500, height: 600)
        .windowBackground(useGradient: settings.useGradientTheme)
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedIcon: $selectedIcon)
        }
        .alert("Duplicate Command Name", isPresented: $showDuplicateAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A command with this name already exists. Please choose a different name.")
        }
    }
}
