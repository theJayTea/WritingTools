import SwiftUI

struct UnifiedCommandButton: View {
    let command: UnifiedCommand
    let isEditing: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let isLoading: Bool

    var body: some View {
        Button(action: {
            if !isEditing {
                onTap()
            }
        }) {
            HStack {
                if isEditing {
                    Button(action: onDelete) {
                        Image(systemName: "minus.circle")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .buttonStyle(.borderless)
                }
                
                
                HStack(spacing: 4) {
                    Image(systemName: command.icon)
                    Text(command.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                if isEditing {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
            .frame(maxWidth: 140)
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
        }
        .buttonStyle(LoadingButtonStyle(isLoading: isLoading))
        .disabled(isLoading)
    }
}

