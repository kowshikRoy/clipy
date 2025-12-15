import SwiftUI

struct FooterView: View {
    @ObservedObject var focusManager: AppFocusManager
    
    // Actions for the menu
    let onPasteToApp: () -> Void
    let onCopyToClipboard: () -> Void
    let onEdit: () -> Void
    let onPin: () -> Void
    let onAddMetadata: () -> Void
    let onDelete: () -> Void
    let onDeleteAll: () -> Void
    let onDeleteMetadata: () -> Void // New callback
    let hasMetadata: Bool // New state check
    
    @State private var showActionsMenu = false

    var body: some View {
        HStack(spacing: 0) {
            // Left: Label
            HStack(spacing: 8) {
                Image(systemName: "clipboard")
                    .foregroundColor(.white) // Or custom color if needed
                Text("Clipy")
                    .font(.custom("Roboto", size: 13))
                    .foregroundColor(.luminaTextSecondary)
            }
            
            Spacer()
            
            // Right: Shortcuts & Actions
            HStack(spacing: 16) {
                // Paste to App
                Button(action: onPasteToApp) {
                    HStack(spacing: 6) {
                        if let icon = focusManager.previousApp?.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "app.dashed")
                                .font(.system(size: 14))
                                .foregroundColor(.luminaTextSecondary)
                        }
                        
                        Text("Paste to \(focusManager.previousApp?.localizedName ?? "App")")
                            .font(.custom("Roboto", size: 13))
                            .fontWeight(.medium)
                            .foregroundColor(.luminaTextPrimary)
                        
                        Image(systemName: "return")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black.opacity(0.6))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(4)
                    }
                }
                .buttonStyle(.plain)

                // Actions Button
                Button(action: { showActionsMenu = true }) {
                    HStack(spacing: 6) {
                        Text("Actions")
                            .font(.custom("Roboto", size: 13))
                            .fontWeight(.medium)
                            .foregroundColor(.luminaTextPrimary)
                        
                        HStack(spacing: 2) {
                            Text("⌘")
                                .font(.system(size: 11))
                            Text("K")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.black.opacity(0.6))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(4)
                    }
                }
                .buttonStyle(.plain)
                .keyboardShortcut("k", modifiers: [.command]) // Cmd+K trigger
                .popover(isPresented: $showActionsMenu, arrowEdge: .bottom) {
                    ActionsMenu(
                        targetAppName: focusManager.previousApp?.localizedName ?? "App",
                        hasMetadata: hasMetadata,
                        onPasteToApp: {
                            showActionsMenu = false
                            onPasteToApp()
                        },
                        onCopyToClipboard: {
                            showActionsMenu = false
                            onCopyToClipboard()
                        },
                        onEdit: {
                            showActionsMenu = false
                            onEdit()
                        },
                        onPin: {
                            showActionsMenu = false
                            onPin()
                        },
                        onAddMetadata: {
                            showActionsMenu = false
                            onAddMetadata()
                        },
                        onDeleteMetadata: {
                            showActionsMenu = false
                            onDeleteMetadata()
                        },
                        onDelete: {
                            showActionsMenu = false
                            onDelete()
                        },
                        onDeleteAll: {
                            showActionsMenu = false
                            onDeleteAll()
                        }
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.obsidianSurface.opacity(0.9)) // Darker footer background
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.obsidianBorder),
            alignment: .top
        )
    }
}

struct ActionsMenu: View {
    let targetAppName: String
    let hasMetadata: Bool
    let onPasteToApp: () -> Void
    let onCopyToClipboard: () -> Void
    let onEdit: () -> Void
    let onPin: () -> Void
    let onAddMetadata: () -> Void
    let onDeleteMetadata: () -> Void
    let onDelete: () -> Void
    let onDeleteAll: () -> Void
    
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool

    // Using a simpler struct without ID since we will iterate by index or make ID computed/stable if needed.
    // However, iterating by index is safest for computed lists.
    struct MenuItem {
        let icon: String
        let text: String
        let shortcut: String
        var color: Color = .primary
        let action: () -> Void
    }

    var items: [MenuItem] {
        var list = [
            MenuItem(icon: "arrow.turn.up.left", text: "Paste to \(targetAppName)", shortcut: "↵", action: onPasteToApp),
            MenuItem(icon: "doc.on.doc", text: "Copy to Clipboard", shortcut: "⌘↵", action: onCopyToClipboard),
            MenuItem(icon: "pencil", text: "Edit entry", shortcut: "", action: onEdit),
            MenuItem(icon: "pin", text: "Pin entry", shortcut: "", action: onPin)
        ]

        if hasMetadata {
            list.append(MenuItem(icon: "tag", text: "Edit Metadata", shortcut: "", action: onAddMetadata))
            list.append(MenuItem(icon: "tag.slash", text: "Delete Metadata", shortcut: "", action: onDeleteMetadata))
        } else {
            list.append(MenuItem(icon: "tag", text: "Add Metadata", shortcut: "", action: onAddMetadata))
        }

        list.append(MenuItem(icon: "trash", text: "Delete entry", shortcut: "⌫", action: onDelete))
        list.append(MenuItem(icon: "trash.slash", text: "Delete all entries", shortcut: "", color: .red, action: onDeleteAll))

        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Using indices to ensure stability. The list is small enough.
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                Group {
                    if index == 2 {
                        Divider().background(Color.gray.opacity(0.3))
                    }
                    if index == items.count - 1 {
                        Divider().background(Color.gray.opacity(0.3))
                    }

                    MenuButton(
                        icon: item.icon,
                        text: item.text,
                        shortcut: item.shortcut,
                        color: item.color,
                        isSelected: index == selectedIndex,
                        action: item.action,
                        onHover: { hovering in
                            if hovering {
                                selectedIndex = index
                            }
                        }
                    )
                }
            }
        }
        .padding(8)
        .frame(width: 250)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
        .onAppear {
            // Monitor for local events (Up/Down/Return) while the menu is open
            // We use a local monitor so we don't interfere with other apps, but we catch events before they hit the view hierarchy if needed,
            // or we can use a simpler approach: just listening on the window.
            // Since this is a popover, it has its own window usually.
            
            // However, SwiftUI Popovers can be tricky. Let's try adding the monitor to the local event loop.
            
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 126: // Up Arrow
                    selectedIndex = max(0, selectedIndex - 1)
                    return nil // Consume event
                case 125: // Down Arrow
                    selectedIndex = min(items.count - 1, selectedIndex + 1)
                    return nil // Consume event
                case 36: // Return
                    if selectedIndex >= 0 && selectedIndex < items.count {
                        items[selectedIndex].action()
                    }
                    return nil // Consume event
                case 53: // Esc
                     // Let it pass through to close the popover (default behavior)
                    return event
                default:
                    return event
                }
            }
        }
        .onDisappear {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
    
    @State private var monitor: Any?
}

struct MenuButton: View {
    let icon: String
    let text: String
    let shortcut: String
    var color: Color = .primary
    let isSelected: Bool
    let action: () -> Void
    let onHover: (Bool) -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(text)
                Spacer()
                if !shortcut.isEmpty {
                    Text(shortcut)
                    .font(.caption)
                    .foregroundColor(.gray)
                }
            }
            .foregroundColor(color)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            onHover(hovering)
        }
    }
}
