import SwiftUI

struct CustomCommandsView: View {
    @ObservedObject var commandsManager: CustomCommandsManager
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
                        .foregroundColor(.secondary)
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
        .background(Color(.windowBackgroundColor))
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
                    .foregroundColor(.secondary)
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
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 8)
    }
}

struct CustomCommandEditor: View {
    @ObservedObject var commandsManager: CustomCommandsManager
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
                        .foregroundColor(.secondary)
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
                            TextField("Command Name", text: $name)
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
                                        .foregroundColor(.accentColor)
                                    Text("Change Icon")
                                        .foregroundColor(.accentColor)
                                }
                                .padding(8)
                                .background(Color(.controlBackgroundColor))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Prompt field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prompt")
                            .font(.headline)
                        TextEditor(text: $prompt)
                            .frame(height: 150)
                            .font(.body)
                            .padding(4)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(6)
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
                        .foregroundColor(.secondary)
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
        .background(Color(.windowBackgroundColor))
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedIcon: $selectedIcon)
        }
    }
}

struct IconPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedIcon: String
    
    let icons = [
        "star.fill", "heart.fill", "bolt.fill", "leaf.fill", "globe",
        "text.bubble.fill", "pencil", "doc.fill", "book.fill", "bookmark.fill",
        "tag.fill", "checkmark.circle.fill", "bell.fill", "flag.fill", "paperclip",
        "link", "quote.bubble.fill", "list.bullet", "chart.bar.fill", "arrow.right.circle.fill",
        "arrow.triangle.2.circlepath", "magnifyingglass", "lightbulb.fill", "wand.and.stars",
        "brain.head.profile", "character.bubble", "globe.europe.africa.fill",
        "globe.americas.fill", "globe.asia.australia.fill", "character", "textformat",
        "folder.fill", "pencil.tip.crop.circle", "paintbrush", "text.justify", "scissors",
        "doc.on.clipboard", "arrow.up.doc", "arrow.down.doc", "doc.badge.plus",
        "bookmark.circle.fill", "bubble.left.and.bubble.right", "doc.text.magnifyingglass",
        "checkmark.rectangle", "trash", "quote.bubble", "abc", "globe.badge.chevron.backward",
        "character.book.closed", "book", "rectangle.and.text.magnifyingglass",
        "keyboard", "text.redaction", "a.magnify", "character.textbox",
        "character.cursor.ibeam", "cursorarrow.and.square.on.square.dashed", "rectangle.and.pencil.and.ellipsis",
        "bubble.middle.bottom", "bubble.left", "text.badge.star", "text.insert", "arrow.uturn.backward.circle.fill"
    ]
    
    let columns = Array(repeating: GridItem(.flexible()), count: 8)
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Icon")
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
            
            // Icons grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(icons, id: \.self) { icon in
                        Button(action: {
                            selectedIcon = icon
                            dismiss()
                        }) {
                            Image(systemName: icon)
                                .font(.title2)
                                .frame(width: 32, height: 32)
                                .foregroundColor(selectedIcon == icon ? .white : .primary)
                                .background(selectedIcon == icon ? Color.accentColor : Color.clear)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 300)
        .background(Color(.windowBackgroundColor))
    }
}
