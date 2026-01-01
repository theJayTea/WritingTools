import SwiftUI
import Observation

struct CommandsView: View {
    @Bindable var commandManager: CommandManager
    @Bindable private var settings = AppSettings.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var isAddingNew = false
    @State private var editingCommand: CommandModel?
    @State private var newCommand = CommandModel(name: "", prompt: "", icon: "text.bubble")
    @State private var showingResetAlert = false
    @State private var selectedTab = 0 // 0 for built-in, 1 for custom
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with enhanced styling
            HStack {
                Text("Manage Commands")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding()
            
            // Tab switcher with improved styling
            Picker("Command Type", selection: $selectedTab) {
                Text("Built-in").tag(0)
                Text("Custom").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            // Command list with section header
            VStack(alignment: .leading, spacing: 8) {
                Text(selectedTab == 0 ? "Built-in Commands" : "Custom Commands")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                if selectedTab == 0 {
                    builtInCommandsView
                } else {
                    customCommandsView
                }
            }
            
            Divider()
            
            // Action buttons with enhanced styling
            HStack {
                if selectedTab == 0 {
                    Button(action: { showingResetAlert = true }) {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                            .font(.body)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding()
                    .help("Reset all built-in commands to their original state, including restoring any that were deleted")
                } else {
                    Button(action: { isAddingNew = true }) {
                        Label("Add Custom Command", systemImage: "plus.circle.fill")
                            .font(.body)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding()
                }
                
                Spacer()
            }
        }
        .frame(width: 600, height: 500)
        .windowBackground(useGradient: settings.useGradientTheme)
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
        .listStyle(.inset)
        .overlay(
            Group {
                if commandManager.builtInCommands.isEmpty {
                    VStack {
                        Image(systemName: "questionmark.circle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No built-in commands")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        )
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
        .listStyle(.inset)
        .overlay(
            Group {
                if commandManager.customCommands.isEmpty {
                    VStack {
                        Image(systemName: "plus.circle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No custom commands yet")
                            .foregroundStyle(.secondary)
                        Text("Add one to get started")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        )
    }
}

struct CommandRow: View {
    let command: CommandModel
    let onEdit: (CommandModel) -> Void
    let onDelete: (CommandModel) -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon with consistent size and styling
            Image(systemName: command.icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(command.name)
                    .font(.headline)
                
                Text(command.isBuiltIn ? "Built-in" : "Custom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(command.isBuiltIn ?
                                  Color.blue.opacity(0.2) :
                                  Color.green.opacity(0.2))
                    )
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: { onEdit(command) }) {
                    Image(systemName: "pencil")
                        .font(.body)
                        .foregroundStyle(.blue)
                        .frame(width: 28, height: 28)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(.circle)
                }
                .buttonStyle(.plain)
                .help("Edit command")
                
                Button(action: { onDelete(command) }) {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundStyle(.red)
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.1))
                        .clipShape(.circle)
                }
                .buttonStyle(.plain)
                .help("Delete command")
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

#Preview {
    CommandsView(commandManager: CommandManager())
}
