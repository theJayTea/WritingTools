import SwiftUI

struct CustomCommandsView: View {
    @ObservedObject var commandsManager: CustomCommandsManager
    @Bindable private var settings = AppSettings.shared
    @Environment(\.dismiss) var dismiss
    @State private var isAddingNew = false
    @State private var selectedCommand: CustomCommand?
    @State private var editingCommand: CustomCommand?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Custom Commands")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            // List of commands
            List {
                ForEach(commandsManager.commands) { command in
                    CustomCommandRow(
                        command: command,
                        onEdit: { editingCommand = $0 },
                        onDelete: { commandsManager.deleteCommand($0) }
                    )
                }
            }
            
            Divider()
            
            // Add button
            HStack {
                Button(action: { isAddingNew = true }) {
                    Label("Add Custom Command", systemImage: "plus.circle.fill")
                        .font(.body)
                }
                .controlSize(.large)
                .padding()
                
                Spacer()
            }
        }
        .frame(width: 500, height: 400)
        .windowBackground(useGradient: settings.useGradientTheme)
        .sheet(isPresented: $isAddingNew) {
            CustomCommandEditor(
                commandsManager: commandsManager,
                isPresented: $isAddingNew
            )
        }
        .sheet(item: $editingCommand) { command in
            CustomCommandEditor(
                commandsManager: commandsManager,
                isPresented: .constant(true),
                editingCommand: command
            )
        }
    }
}

struct CustomCommandRow: View {
    let command: CustomCommand
    var onEdit: (CustomCommand) -> Void
    var onDelete: (CustomCommand) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: command.icon)
                .font(.title2)
                .frame(width: 30)
            
            // Command Details
            VStack(alignment: .leading, spacing: 4) {
                Text(command.name)
                    .font(.headline)
                Text(command.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            
            // Edit Button
            Button(action: { onEdit(command) }) {
                Image(systemName: "pencil")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            
            // Delete Button
            Button(action: { onDelete(command) }) {
                Image(systemName: "trash")
                    .font(.title2)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 8)
    }
}

struct CustomCommandEditor: View {
    @ObservedObject var commandsManager: CustomCommandsManager
    @Bindable private var settings = AppSettings.shared
    @Binding var isPresented: Bool
    @Environment(\.dismiss) var dismiss
    
    var editingCommand: CustomCommand?
    
    @State private var name: String = ""
    @State private var prompt: String = ""
    @State private var selectedIcon: String = "star.fill"
    @State private var useResponseWindow: Bool = false
    @State private var showingIconPicker = false
    
    init(commandsManager: CustomCommandsManager, isPresented: Binding<Bool>, editingCommand: CustomCommand? = nil) {
        self.commandsManager = commandsManager
        self._isPresented = isPresented
        self.editingCommand = editingCommand
        
        if let command = editingCommand {
            _name = State(initialValue: command.name)
            _prompt = State(initialValue: command.prompt)
            _selectedIcon = State(initialValue: command.icon)
            _useResponseWindow = State(initialValue: command.useResponseWindow)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(editingCommand != nil ? "Edit Command" : "New Command")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            ScrollView {
                VStack(spacing: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        // Name field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.headline)
                            TextField("Button Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        // Icon selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Icon")
                                .font(.headline)
                            Button(action: { showingIconPicker = true }) {
                                HStack {
                                    Image(systemName: selectedIcon)
                                        .font(.title2)
                                        .foregroundStyle(Color.accentColor)
                                    Text("Change Icon")
                                        .foregroundStyle(Color.accentColor)
                                }
                                .padding(8)
                                .background(Color(.controlBackgroundColor))
                                .clipShape(.rect(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Prompt field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What should your AI do with your selected text? (Prompt)")
                            .font(.headline)
                        TextEditor(text: $prompt)
                            .frame(height: 150)
                            .font(.body)
                            .padding(4)
                            .background(Color(.textBackgroundColor))
                            .clipShape(.rect(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    }
                    // Add Response Window Toggle
                    Toggle("Show Response in Chat Window", isOn: $useResponseWindow)
                        .padding(.horizontal)
                    
                    Text("When enabled, responses will appear in a chat window instead of replacing the selected text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                .padding()
            }
            
            Divider()
            
            // Bottom buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button("Save") {
                    let command = CustomCommand(
                        id: editingCommand?.id ?? UUID(),
                        name: name,
                        prompt: prompt,
                        icon: selectedIcon,
                        useResponseWindow: useResponseWindow
                    )
                    
                    if editingCommand != nil {
                        commandsManager.updateCommand(command)
                    } else {
                        commandsManager.addCommand(command)
                    }
                    
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(name.isEmpty || prompt.isEmpty)
                .padding()
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .windowBackground(useGradient: settings.useGradientTheme)
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedIcon: $selectedIcon, availableIcons: nil)
        }
    }
}
