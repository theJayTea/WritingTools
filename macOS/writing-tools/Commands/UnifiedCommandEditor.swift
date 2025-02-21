import SwiftUI

struct UnifiedCommandEditor: View {
    @Binding var command: UnifiedCommand
    var onSave: () -> Void
    var onCancel: () -> Void

    @State private var name: String
    @State private var prompt: String
    @State private var selectedIcon: String
    @State private var useResponseWindow: Bool
    @State private var showingIconPicker = false

    init(command: Binding<UnifiedCommand>, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self._command = command
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: command.wrappedValue.name)
        _prompt = State(initialValue: command.wrappedValue.prompt)
        _selectedIcon = State(initialValue: command.wrappedValue.icon)
        _useResponseWindow = State(initialValue: command.wrappedValue.useResponseWindow)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Command")
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
                                .background(Color(NSColor.controlBackgroundColor))
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
                            .padding(4)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    }
                    
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
            
            // Footer Buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button("Save") {
                    // Update the bound command
                    command.name = name
                    command.prompt = prompt
                    command.icon = selectedIcon
                    command.useResponseWindow = useResponseWindow
                    onSave()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(name.isEmpty || prompt.isEmpty)
                .padding()
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedIcon: $selectedIcon)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
