import SwiftUI

struct CommandsView: View {
    @ObservedObject var commandManager: CommandManager
    @Environment(\.dismiss) var dismiss
    
    @State private var isAddingNew = false
    @State private var editingCommand: CommandModel?
    @State private var newCommand = CommandModel(name: "", prompt: "", icon: "text.bubble")
    @State private var showingResetAlert = false
    @State private var selectedTab = 0 // 0 for built-in, 1 for custom
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Commands")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            // Tab switcher
            Picker("Command Type", selection: $selectedTab) {
                Text("Built-in").tag(0)
                Text("Custom").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            // Command list
            if selectedTab == 0 {
                builtInCommandsView
            } else {
                customCommandsView
            }
            
            Divider()
            
            // Action buttons
            HStack {
                if selectedTab == 0 {
                    Button(action: { showingResetAlert = true }) {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                            .font(.body)
                    }
                    .controlSize(.large)
                    .padding()
                    .help("Reset all built-in commands to their original state, including restoring any that were deleted")
                } else {
                    Button(action: { isAddingNew = true }) {
                        Label("Add Custom Command", systemImage: "plus.circle.fill")
                            .font(.body)
                    }
                    .controlSize(.large)
                    .padding()
                }
                
                Spacer()
            }
        }
        .frame(width: 600, height: 500)
        .sheet(isPresented: $isAddingNew) {
            CommandEditor(
                command: $newCommand,
                onSave: {
                    commandManager.addCommand(newCommand)
                    newCommand = CommandModel(name: "", prompt: "", icon: "text.bubble")
                    isAddingNew = false
                },
                onCancel: {
                    newCommand = CommandModel(name: "", prompt: "", icon: "text.bubble")
                    isAddingNew = false
                }
            )
        }
        .sheet(item: $editingCommand) { command in
            // Make a copy for editing
            let commandCopy = command
            let binding = Binding(
                get: { commandCopy },
                set: { updatedCommand in
                    // When saving, update the command in the manager
                    commandManager.updateCommand(updatedCommand)
                    editingCommand = nil
                }
            )
            
            CommandEditor(
                command: binding,
                onSave: {
                    // The binding's setter will handle the update
                },
                onCancel: {
                    editingCommand = nil
                },
                commandManager: commandManager
            )
        }
        .alert("Reset Built-in Commands", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                commandManager.resetToDefaults()
            }
        } message: {
            Text("This will reset all built-in commands to their original settings, restore any deleted built-in commands, and keep your custom commands. This action cannot be undone.")
        }
    }
    
    var builtInCommandsView: some View {
        List {
            ForEach(commandManager.builtInCommands) { command in
                CommandRow(
                    command: command,
                    onEdit: { command in editingCommand = command },
                    onDelete: { command in commandManager.deleteCommand(command) }
                )
            }
        }
    }
    
    var customCommandsView: some View {
        List {
            ForEach(commandManager.customCommands) { command in
                CommandRow(
                    command: command,
                    onEdit: { command in editingCommand = command },
                    onDelete: { command in commandManager.deleteCommand(command) }
                )
            }
            .onMove { source, destination in
                // Filter to only get custom commands, then apply the move
                var customCommands = commandManager.customCommands
                customCommands.move(fromOffsets: source, toOffset: destination)
                
                // Get the built-in commands
                let builtInCommands = commandManager.builtInCommands
                
                // Recreate the full commands array with the new order
                let newCommands = builtInCommands + customCommands
                
                // Update the manager using the public method
                commandManager.replaceAllCommands(with: newCommands)
            }
        }
        // Use a different approach instead of editMode for macOS
        .onAppear {
            // In macOS, the list will have drag handles by default when .onMove is used
        }
    }
}

struct CommandRow: View {
    let command: CommandModel
    let onEdit: (CommandModel) -> Void
    let onDelete: (CommandModel) -> Void
    
    var body: some View {
        HStack {
            Image(systemName: command.icon)
                .frame(width: 30)
            
            VStack(alignment: .leading) {
                Text(command.name)
                    .fontWeight(.medium)
                
                Text(command.isBuiltIn ? "Built-in" : "Custom")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { onEdit(command) }) {
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            
            // Allow deletion of any command
            Button(action: { onDelete(command) }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    CommandsView(commandManager: CommandManager())
} 