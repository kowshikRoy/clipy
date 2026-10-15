import SwiftUI

struct FooterView: View {
    @ObservedObject var focusManager: AppFocusManager
    @ObservedObject var permissionMonitor: PermissionMonitor
    
    // Actions for the menu
    let onPasteToApp: () -> Void
    let onCopyToClipboard: () -> Void
    let onEdit: () -> Void
    let onPin: () -> Void
    let onAddMetadata: () -> Void
    let onDelete: () -> Void
    let onDeleteAll: () -> Void
    let onDeleteMetadata: () -> Void
    let hasMetadata: Bool
    var isPinned: Bool = false
    var hasURL: Bool = false
    var onOpenURL: (() -> Void)? = nil
    
    @State private var showActionsMenu = false

    private static let versionString: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        let buildDate: Date
        if let execPath = Bundle.main.executablePath,
           let attributes = try? FileManager.default.attributesOfItem(atPath: execPath),
           let modDate = attributes[.modificationDate] as? Date {
            buildDate = modDate
        } else if let bundlePath = Bundle.main.resourcePath,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: bundlePath),
                  let modDate = attributes[.modificationDate] as? Date {
            buildDate = modDate
        } else {
            buildDate = Date()
        }
        
        return "v\(formatter.string(from: buildDate))"
    }()

    var body: some View {
        HStack(spacing: 0) {
            // Left: Label
            HStack(spacing: 8) {
                Image(systemName: "clipboard")
                    .foregroundColor(.white) // Or custom color if needed
                Text("Clipy")
                    .font(.custom("Roboto", size: 13))
                    .foregroundColor(.luminaTextSecondary)
                Text(Self.versionString)
                    .font(.system(size: 11))
                    .foregroundColor(.luminaTextSecondary.opacity(0.6))

                if !permissionMonitor.isTrusted {
                    Button(action: {
                        permissionMonitor.openAccessibilitySettings()
                    }) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Enable Accessibility access for Auto-Paste")
                }
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
                        isPinned: isPinned,
                        hasURL: hasURL,
                        onPasteToApp: {
                            showActionsMenu = false
                            onPasteToApp()
                        },
                        onCopyToClipboard: {
                            showActionsMenu = false
                            onCopyToClipboard()
                        },
                        onOpenURL: {
                            showActionsMenu = false
                            onOpenURL?()
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
        .background(Color.obsidianSurface.opacity(0.9).ignoresSafeArea(edges: .bottom)) // Darker footer background
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
    var isPinned: Bool = false
    var hasURL: Bool = false
    let onPasteToApp: () -> Void
    let onCopyToClipboard: () -> Void
    var onOpenURL: (() -> Void)? = nil
    let onEdit: () -> Void
    let onPin: () -> Void
    let onAddMetadata: () -> Void
    let onDeleteMetadata: () -> Void
    let onDelete: () -> Void
    let onDeleteAll: () -> Void
    
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool

    struct MenuItem {
        let icon: String
        let text: LocalizedStringKey
        let isDeleteEntry: Bool
        let shortcut: String
        var color: Color = .primary
        let action: () -> Void
        
        init(icon: String, text: LocalizedStringKey, isDeleteEntry: Bool = false, shortcut: String, color: Color = .primary, action: @escaping () -> Void) {
            self.icon = icon
            self.text = text
            self.isDeleteEntry = isDeleteEntry
            self.shortcut = shortcut
            self.color = color
            self.action = action
        }
    }

    var items: [MenuItem] {
        var list = [
            MenuItem(icon: "arrow.turn.up.left", text: "Paste to \(targetAppName)", shortcut: "↵", action: onPasteToApp),
            MenuItem(icon: "doc.on.doc", text: "Copy to Clipboard", shortcut: "⌘↵", action: onCopyToClipboard)
        ]
        
        if hasURL, let onOpenURL = onOpenURL {
            list.append(MenuItem(icon: "safari", text: "Open Link in Browser", shortcut: "⌘O", action: onOpenURL))
        }
        
        list.append(MenuItem(icon: "pencil", text: "Edit entry", shortcut: "⌘E", action: onEdit))
        list.append(MenuItem(icon: isPinned ? "pin.slash" : "pin", text: isPinned ? "Unpin entry" : "Pin entry", shortcut: "⌘P", action: onPin))

        if hasMetadata {
            list.append(MenuItem(icon: "tag", text: "Edit Metadata", shortcut: "⌘M", action: onAddMetadata))
            list.append(MenuItem(icon: "tag.slash", text: "Delete Metadata", shortcut: "", action: onDeleteMetadata))
        } else {
            list.append(MenuItem(icon: "tag", text: "Add Metadata", shortcut: "⌘M", action: onAddMetadata))
        }

        list.append(MenuItem(icon: "trash", text: "Delete entry", isDeleteEntry: true, shortcut: "⌫", action: onDelete))
        list.append(MenuItem(icon: "trash.slash", text: "Delete all entries", shortcut: "", color: .red, action: onDeleteAll))

        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                Group {
                    if index == (hasURL ? 3 : 2) {
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
                case 51: // Delete / Backspace
                    if let deleteItem = items.first(where: { $0.isDeleteEntry }) {
                        deleteItem.action()
                    }
                    return nil // Consume event
                case 53: // Esc
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
    let text: LocalizedStringKey
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
