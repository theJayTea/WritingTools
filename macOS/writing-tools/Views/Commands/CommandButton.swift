import SwiftUI

struct CommandButton: View {
    let command: CommandModel
    let isEditing: Bool
    let isLoading: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        ZStack {
            // Main button wrapper
            Button(action: {
                if !isEditing && !isLoading {
                    onTap()
                }
            }) {
                HStack {
                    // Leave space for the delete button if in edit mode
                    if isEditing {
                        Color.clear
                            .frame(width: 10, height: 16)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: command.icon)
                        Text(command.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    
                    // Leave space for the edit button if in edit mode
                    if isEditing {
                        Color.clear
                            .frame(width: 10, height: 16)
                    }
                }
                .frame(maxWidth: 140)
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
            .buttonStyle(LoadingButtonStyle(isLoading: isLoading))
            .disabled(isLoading || isEditing)
            
            // Overlay edit controls when in edit mode
            if isEditing {
                HStack {
                    Button(action: onDelete) {
                        Image(systemName: "minus.circle")
                            .foregroundColor(.red)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle")
                            .foregroundColor(.blue)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: 140)
                .padding(.horizontal, 8)
            }
        }
    }
}

struct LoadingButtonStyle: ButtonStyle {
    var isLoading: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isLoading ? 0.5 : 1.0)
            .overlay(
                Group {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                }
            )
    }
}

#Preview {
    VStack {
        CommandButton(
            command: CommandModel.proofread,
            isEditing: false,
            isLoading: false,
            onTap: {},
            onEdit: {},
            onDelete: {}
        )
        
        CommandButton(
            command: CommandModel.proofread,
            isEditing: true,
            isLoading: false,
            onTap: {},
            onEdit: {},
            onDelete: {}
        )
    }
} 
