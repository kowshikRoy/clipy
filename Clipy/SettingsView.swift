
import SwiftUI
import Combine
import Carbon

// MARK: - App Settings Model

@MainActor
class AppSettings: ObservableObject {
    @Published var blockedApps: [String] = [] {
        didSet {
            save(blockedApps, key: "blockedApps")
        }
    }
    
    @Published var blockedHosts: [String] = [] {
        didSet {
            save(blockedHosts, key: "blockedHosts")
        }
    }
    
    @Published var hotkeyKeyCode: Int {
        didSet {
             UserDefaults.standard.set(hotkeyKeyCode, forKey: "hotkeyKeyCode")
        }
    }
    
    @Published var hotkeyModifiers: Int {
        didSet {
            UserDefaults.standard.set(hotkeyModifiers, forKey: "hotkeyModifiers")
        }
    }
    
    init() {
        self.blockedApps = AppSettings.load(key: "blockedApps")
        self.blockedHosts = AppSettings.load(key: "blockedHosts")
        
        // Default to Cmd+Shift+V
        self.hotkeyKeyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int ?? kVK_ANSI_V
        self.hotkeyModifiers = UserDefaults.standard.object(forKey: "hotkeyModifiers") as? Int ?? cmdKey + shiftKey
    }
    
    func isBlocked(app: String?, host: String?) -> Bool {
        if let app = app, blockedApps.contains(app) {
            return true
        }
        if let host = host, blockedHosts.contains(host) {
            return true
        }
        return false
    }
    
    // MARK: - Persistence
    
    private static func load(key: String) -> [String] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return list
    }
    
    private func save(_ list: [String], key: String) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Settings View

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case privacy = "Privacy"
    case about = "About"
    
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .privacy: return "hand.raised"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var activeTab: SettingsTab = .general
    
    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Sidebar
            VStack(spacing: 0) { // Zero spacing, padding handled by button
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SidebarButton(tab: tab, isActive: activeTab == tab) {
                        activeTab = tab
                    }
                }
                Spacer()
            }
            .padding(.top, 20) // Top padding matches content area roughly
            .padding(.horizontal, 10)
            .frame(width: 200) // Increased width slightly to accommodate new padding
            .background(Color.obsidianBackground.opacity(0.6)) // Matching opacity
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(Color.obsidianBorder),
                alignment: .trailing
            )
            
            // MARK: - Content
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading) {
                        if activeTab == .general {
                            GeneralSettingsView(settings: settings)
                        } else if activeTab == .privacy {
                            PrivacySettingsView(settings: settings)
                        } else {
                            AboutSettingsView()
                        }
                    }
                    .padding(30) // More generous padding
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.obsidianBackground.opacity(0.6)) // Translucent background to show VisualEffectView
        }
        .frame(width: 650, height: 400) // Adjusted frame
        .background(VisualEffectView().ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// MARK: - Sub Views

// MARK: - Sidebar Button Matching LuminaRow
struct SidebarButton: View {
    let tab: SettingsTab
    let isActive: Bool
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isActive ? tab.icon + ".fill" : tab.icon)
                    .font(.system(size: 14))
                    .foregroundColor(isActive ? .luminaTextPrimary : .luminaTextSecondary)
                    .frame(width: 20, height: 20)
                
                Text(tab.rawValue)
                    .font(.custom("Roboto", size: 13))
                    .fontWeight(.regular)
                    .foregroundColor(isActive ? .luminaTextPrimary : .luminaTextSecondary)
                
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.white.opacity(0.15) : (isHovering ? Color.white.opacity(0.08) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                     .stroke(isActive ? Color.white.opacity(0.2) : Color.clear, lineWidth: 0.5)
            )
            .padding(.leading, 12)
            .padding(.trailing, 4)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("General")
                .font(.custom("Roboto", size: 20))
                .fontWeight(.medium)
                .foregroundColor(.luminaTextPrimary)
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Global Shortcut")
                    .font(.custom("Roboto", size: 14))
                    .foregroundColor(.luminaTextSecondary)
                
                ShortcutRecorder(keyCode: $settings.hotkeyKeyCode, modifiers: $settings.hotkeyModifiers) {
                    // Update hotkey registration when changed
                    let manager = HotKeyManager.shared
                    manager.registerHotKey(keyCode: UInt32(settings.hotkeyKeyCode), modifiers: UInt32(settings.hotkeyModifiers))
                }
                
                Text("Press this shortuct to toggle Clipy.")
                    .font(.custom("Roboto", size: 12))
                    .foregroundColor(.luminaTextSecondary.opacity(0.7))
            }
            .padding(20)
            .background(Color.obsidianSurface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.obsidianBorder, lineWidth: 0.5)
            )
        }
    }
}

struct ShortcutRecorder: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    var onChange: () -> Void
    
    @State private var isRecording = false
    @State private var monitor: Any?
    
    var body: some View {
        Button(action: {
            isRecording.toggle()
            if isRecording {
                startRecording()
            } else {
                stopRecording()
            }
        }) {
            HStack(spacing: 8) {
                if isRecording {
                    Image(systemName: "recordingtape")
                        .foregroundColor(.luminaAccent)
                    Text("Type shortcut...")
                        .foregroundColor(.luminaAccent)
                } else {
                    Image(systemName: "keyboard")
                        .foregroundColor(.luminaTextSecondary)
                    Text(keyString)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.luminaTextPrimary)
                }
                
                Spacer()
                
                if isRecording {
                     Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.luminaTextSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 200) // Fixed width for cleaner look
            .background(isRecording ? Color.white.opacity(0.1) : Color.black.opacity(0.3))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.luminaAccent : Color.obsidianBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var keyString: String {
        var string = ""
        
        if modifiers & cmdKey != 0 { string += "⌘ " }
        if modifiers & shiftKey != 0 { string += "⇧ " }
        if modifiers & optionKey != 0 { string += "⌥ " }
        if modifiers & controlKey != 0 { string += "⌃ " }
        
        string += keyDescription(for: keyCode)
        
        return string
    }
    
    private func keyDescription(for code: Int) -> String {
        switch code {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_Quote: return "\""
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Grave: return "`"
        case kVK_ANSI_KeypadDecimal: return "."
        case kVK_ANSI_KeypadMultiply: return "*"
        case kVK_ANSI_KeypadPlus: return "+"
        case kVK_ANSI_KeypadClear: return "Clear"
        case kVK_ANSI_KeypadDivide: return "/"
        case kVK_ANSI_KeypadEnter: return "Enter"
        case kVK_ANSI_KeypadMinus: return "-"
        case kVK_ANSI_KeypadEquals: return "="
        case kVK_ANSI_Keypad0: return "0"
        case kVK_ANSI_Keypad1: return "1"
        case kVK_ANSI_Keypad2: return "2"
        case kVK_ANSI_Keypad3: return "3"
        case kVK_ANSI_Keypad4: return "4"
        case kVK_ANSI_Keypad5: return "5"
        case kVK_ANSI_Keypad6: return "6"
        case kVK_ANSI_Keypad7: return "7"
        case kVK_ANSI_Keypad8: return "8"
        case kVK_ANSI_Keypad9: return "9"
        case kVK_Return: return "Enter"
        case kVK_Tab: return "Tab"
        case kVK_Space: return "Space"
        case kVK_Delete: return "Delete"
        case kVK_Escape: return "Esc"
        default: return "?"
        }
    }
    
    private func startRecording() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Ignore single modifier keys
            if event.modifierFlags.contains(.command) || 
               event.modifierFlags.contains(.control) || 
               event.modifierFlags.contains(.option) || 
               event.modifierFlags.contains(.shift) {
                   
               // Only if there is a non-modifier key pressed?
               // Actually we want to capture the combo.
            }
            
            // Map NSEvent modifiers to Carbon modifiers
            var carbonModifiers: Int = 0
            if event.modifierFlags.contains(.command) { carbonModifiers |= cmdKey }
            if event.modifierFlags.contains(.shift) { carbonModifiers |= shiftKey }
            if event.modifierFlags.contains(.option) { carbonModifiers |= optionKey }
            if event.modifierFlags.contains(.control) { carbonModifiers |= controlKey }
            
            // if it's just a modifier key, don't stop recording yet, but usually we just care about the final key down
            // But NSEvent.keyDown only fires when a key is pressed.
            
            self.keyCode = Int(event.keyCode)
            self.modifiers = carbonModifiers
            
            self.stopRecording()
            self.onChange()
            
            return nil // Consume event
        }
    }
    
    private func stopRecording() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "paperclip")
                    .font(.system(size: 56))
                    .foregroundColor(.luminaAccent)
                    .padding(24)
                    .background(
                        Circle()
                            .fill(Color.obsidianSurface)
                            .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.obsidianBorder, lineWidth: 1)
                    )
                
                VStack(spacing: 8) {
                    Text("Clipy")
                        .font(.custom("Roboto", size: 32))
                        .fontWeight(.bold)
                        .foregroundColor(.luminaTextPrimary)
                    
                    Text("Version 2.0 (Lumina)")
                        .font(.custom("Roboto", size: 14))
                        .foregroundColor(.luminaTextSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.obsidianSurface)
                        .cornerRadius(20)
                }
            }
            
            VStack(spacing: 12) {
                Text("Designed for speed and simplicity.")
                    .font(.custom("Roboto", size: 14))
                    .foregroundColor(.luminaTextSecondary)
                
                Link("Visit Website", destination: URL(string: "https://clipy-app.com")!)
                    .font(.custom("Roboto", size: 14))
                    .foregroundColor(.luminaAccent)
            }
            
            Spacer()
        }
        .frame(minHeight: 300)
    }
}

struct PrivacySettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var newAppInput: String = ""
    @State private var newHostInput: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Privacy")
                .font(.custom("Roboto", size: 20))
                .fontWeight(.medium)
                .foregroundColor(.luminaTextPrimary)
            
            Text("Manage what creates a history entry. Content from these sources will be ignored.")
                .font(.custom("Roboto", size: 13))
                .foregroundColor(.luminaTextSecondary)
                .padding(.bottom, 8)
            
            // Apps
            VStack(alignment: .leading, spacing: 10) {
                Label("Blocked Applications", systemImage: "app.dashed")
                    .font(.custom("Roboto", size: 13))
                    .fontWeight(.medium)
                    .foregroundColor(.luminaTextPrimary)
                
                HStack(spacing: 12) {
                    TextField("Application Name", text: $newAppInput)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.custom("Roboto", size: 13))
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .foregroundColor(.luminaTextPrimary)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.obsidianBorder, lineWidth: 1))
                    
                    Button(action: addApp) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.luminaAccent)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(newAppInput.isEmpty)
                    .opacity(newAppInput.isEmpty ? 0.5 : 1.0)
                }
                
                if !settings.blockedApps.isEmpty {
                    
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 2) {
                            ForEach(settings.blockedApps, id: \.self) { app in
                                BlockingRow(label: app, icon: "app.dashed") {
                                    removeApp(app)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                    .background(Color.obsidianSurface.opacity(0.5))
                    .cornerRadius(6)
                }
            }
            .padding(16)
            .background(Color.obsidianSurface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.obsidianBorder, lineWidth: 0.5)
            )
            
            // Hosts
            VStack(alignment: .leading, spacing: 10) {
                Label("Blocked Websites", systemImage: "globe")
                    .font(.custom("Roboto", size: 13))
                    .fontWeight(.medium)
                    .foregroundColor(.luminaTextPrimary)
                
                HStack(spacing: 12) {
                    TextField("e.g. google.com", text: $newHostInput)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.custom("Roboto", size: 13))
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .foregroundColor(.luminaTextPrimary)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.obsidianBorder, lineWidth: 1))
                    
                    Button(action: addHost) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.luminaAccent)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(newHostInput.isEmpty)
                    .opacity(newHostInput.isEmpty ? 0.5 : 1.0)
                }
                
                if !settings.blockedHosts.isEmpty {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 2) {
                            ForEach(settings.blockedHosts, id: \.self) { host in
                                BlockingRow(label: host, icon: "globe") {
                                    removeHost(host)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                    .background(Color.obsidianSurface.opacity(0.5))
                    .cornerRadius(6)
                }
            }
            .padding(16)
            .background(Color.obsidianSurface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.obsidianBorder, lineWidth: 0.5)
            )
        }
    }
    
    private func addApp() {
        guard !newAppInput.isEmpty else { return }
        if !settings.blockedApps.contains(newAppInput) {
            settings.blockedApps.append(newAppInput)
        }
        newAppInput = ""
    }
    
    private func removeApp(_ app: String) {
        settings.blockedApps.removeAll { $0 == app }
    }
    
    private func addHost() {
        guard !newHostInput.isEmpty else { return }
        let host = newHostInput.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if !settings.blockedHosts.contains(host) {
            settings.blockedHosts.append(host)
        }
        newHostInput = ""
    }
    
    private func removeHost(_ host: String) {
        settings.blockedHosts.removeAll { $0 == host }
    }
}

struct BlockingRow: View {
    let label: String
    let icon: String
    let onDelete: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.luminaTextSecondary)
                .frame(width: 20)
            
            Text(label)
                .font(.custom("Roboto", size: 13))
                .foregroundColor(.luminaTextPrimary)
            
            Spacer()
            
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.luminaTextSecondary)
                        .frame(width: 20, height: 20)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovering ? Color.white.opacity(0.05) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
}
