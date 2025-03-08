import SwiftUI

struct IconPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedIcon: String
    
    // Default icon set from the original implementation
    let availableIcons: [String]
    
    // Default initialization with our pre-selected set of icons
    init(selectedIcon: Binding<String>, availableIcons: [String]? = nil) {
        self._selectedIcon = selectedIcon
        if let icons = availableIcons {
            self.availableIcons = icons
        } else {
            // Use the original list of icons with 20 additional ones
            self.availableIcons = [
                // Original icons
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
                "bubble.middle.bottom", "bubble.left", "text.badge.star", "text.insert",
                "arrow.uturn.backward.circle.fill", "arrow.uturn.forward.circle.fill",
                "arrow.uturn.left.circle.fill", "arrow.uturn.right.circle.fill",
                "arrow.uturn.up.circle.fill", "arrow.uturn.down.circle.fill",
                
                // Additional 20 modern SF symbols
                "bubble.left.and.text.bubble.right.fill", "text.word.spacing", "captions.bubble.fill",
                "text.alignleft", "text.alignright", "text.aligncenter", "text.badge.checkmark",
                "text.badge.minus", "text.badge.plus", "text.bubble.fill", "gearshape", 
                "sparkle.magnifyingglass", "highlighter", "scribble.variable", "pencil.and.outline",
                "square.and.pencil", "pencil.circle", "pencil.circle.fill", "pencil.tip",
                "rectangle.and.paperclip", "doc.richtext", "doc.plaintext", "doc.append",
                "doc.text.below.ecg", "doc.viewfinder", "sparkles", "wand.and.rays",
                "dial.min", "dial.min.fill", "text.line.first.and.arrowtriangle.forward",
                "paragraph", "list.bullet.circle", "list.number", "list.star", "list.bullet.indent", 
                "photo.stack", "square.stack.3d.up", "square.stack.3d.down.right", "tray.full.fill", 
                "slider.horizontal.3"
            ]
        }
    }
    
    // Use a more compact grid layout with more columns
    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 8)
    
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
                    ForEach(availableIcons, id: \.self) { icon in
                        Button(action: {
                            selectedIcon = icon
                            dismiss()
                        }) {
                            Image(systemName: icon)
                                .font(.title2)
                                .frame(width: 36, height: 36)
                                .foregroundColor(selectedIcon == icon ? .white : .primary)
                                .background(selectedIcon == icon ? Color.accentColor : Color.clear)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            
            Button("Cancel") {
                dismiss()
            }
            .padding()
        }
        .frame(width: 480, height: 480)
    }
} 