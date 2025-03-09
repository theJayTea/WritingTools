import SwiftUI

struct CommandEditor: View {
    @Binding var command: CommandModel
    var onSave: () -> Void
    var onCancel: () -> Void
    var isBuiltIn: Bool
    
    @State private var name: String
    @State private var prompt: String
    @State private var selectedIcon: String
    @State private var useResponseWindow: Bool
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
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isBuiltIn ? "Edit Built-In Command" : "Edit Command")
                    .font(.headline)
                Spacer()
                Button(action: { onCancel() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Name & Icon
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.headline)
                            TextField("Button Name", text: $name)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Icon")
                                .font(.headline)
                            
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
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal)
                    
                    // Display response in window toggle
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Display response in window", isOn: $useResponseWindow)
                            .padding(.horizontal)
                    }
                    
                    // Prompt
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prompt")
                            .font(.headline)
                        
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
                            // Save changes back to the command
                            var updatedCommand = command
                            updatedCommand.name = name
                            updatedCommand.prompt = prompt
                            updatedCommand.icon = selectedIcon
                            updatedCommand.useResponseWindow = useResponseWindow
                            
                            // Update the binding
                            command = updatedCommand
                            
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
                .padding(.vertical)
            }
        }
        .frame(width: 500, height: 600)
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
