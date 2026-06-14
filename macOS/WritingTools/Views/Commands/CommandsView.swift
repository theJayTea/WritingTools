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
                .accessibilityLabel("Close commands manager")
                .accessibilityHint("Dismiss the commands window")
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
        .frame(minWidth: 520, idealWidth: 600, maxWidth: 840, minHeight: 420, idealHeight: 500, maxHeight: 820)
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
                },
                commandManager: commandManager
            )
            // Force SwiftUI to recreate CommandEditor each time the sheet opens,
            // preventing stale @State values from a previous session.
            .id(newCommand.id)
        }
        .sheet(item: $editingCommand) { command in
            EditCommandSheet(
                original: command,
                commandManager: commandManager,
                onDismiss: { editingCommand = nil }
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
                // Reorder only the custom sublist; built-in command positions
                // are preserved, and the full-list replacement, keychain GC,
                // and order-flattening done by replaceAllCommands are avoided.
                // An order-change push is still scheduled via
                // notifyCommandsChanged() inside moveCustomCommand, which is
                // the correct behaviour for keeping iCloud in sync.
                commandManager.moveCustomCommand(fromOffsets: source, toOffset: destination)
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
    @State private var showDeleteConfirmation = false
    
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
                .accessibilityLabel("Edit \(command.name)")
                .accessibilityHint("Open editor for this command")
                
                Button(action: { showDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundStyle(.red)
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.1))
                        .clipShape(.circle)
                }
                .buttonStyle(.plain)
                .help("Delete command")
                .accessibilityLabel("Delete \(command.name)")
                .accessibilityHint("Remove this command")
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .alert("Delete Command", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete(command)
            }
        } message: {
            Text("Are you sure you want to delete \"\(command.name)\"? This action cannot be undone.")
        }
    }
}

/// Wrapper view that owns a mutable @State copy of the command being edited,
/// so the Binding round-trip works correctly inside CommandEditor.
private struct EditCommandSheet: View {
    let original: CommandModel
    let commandManager: CommandManager
    let onDismiss: () -> Void

    @State private var commandCopy: CommandModel

    init(original: CommandModel, commandManager: CommandManager, onDismiss: @escaping () -> Void) {
        self.original = original
        self.commandManager = commandManager
        self.onDismiss = onDismiss
        _commandCopy = State(initialValue: original)
    }

    var body: some View {
        CommandEditor(
            command: $commandCopy,
            onSave: {
                commandManager.updateCommand(commandCopy)
                onDismiss()
            },
            onCancel: {
                onDismiss()
            },
            commandManager: commandManager
        )
    }
}

#Preview {
    CommandsView(commandManager: CommandManager())
}
