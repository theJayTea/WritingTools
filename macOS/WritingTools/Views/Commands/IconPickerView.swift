import SwiftUI

struct IconPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedIcon: String
    @State private var searchText: String = ""
    
    let availableIcons: [String]
    
    init(selectedIcon: Binding<String>, availableIcons: [String]? = nil) {
        self._selectedIcon = selectedIcon
        if let icons = availableIcons {
            self.availableIcons = icons
        } else {
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
                "slider.horizontal.3",
                
                // Additional 20 common and important SF symbols
                "play.fill", "pause.fill", "stop.fill", "plus.circle.fill", "minus.circle.fill",
                "sun.max.fill", "moon.fill", "cloud.fill", "camera.fill", "video.fill",
                "mic.fill", "speaker.fill", "lock.fill", "lock.open.fill", "eye.fill",
                "eye.slash.fill", "hand.thumbsup.fill", "creditcard.fill", "cart.fill", "gift.fill"
            ]
        }
    }
    
    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 8)
    
    var filteredIcons: [String] {
        if searchText.isEmpty {
            return availableIcons
        }
        return availableIcons.filter {
            $0.localizedCaseInsensitiveContains(searchText)
        }
    }
    
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
            
            Divider()
            
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search icons...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            
            Divider()
            
            // Icons grid
            ScrollView {
                if filteredIcons.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No icons found")
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredIcons, id: \.self) { icon in
                            Button(action: {
                                selectedIcon = icon
                                dismiss()
                            }) {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .frame(width: 36, height: 36)
                                    .foregroundColor(
                                        selectedIcon == icon ? .white : .primary
                                    )
                                    .background(
                                        selectedIcon == icon ?
                                        Color.accentColor : Color.clear
                                    )
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .help(icon)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 480, height: 540)
    }
}
