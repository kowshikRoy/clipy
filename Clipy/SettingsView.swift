
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
    @State private var activeTab: SettingsTab = .privacy
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Tab Bar
            HStack(spacing: 0) {
                Spacer()
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button(action: { activeTab = tab }) {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14, weight: .medium))
                            Text(tab.rawValue)
                                .font(.custom("Roboto", size: 11))
                                .fontWeight(.medium)
                        }
                        .foregroundColor(activeTab == tab ? .luminaTextPrimary : .luminaTextSecondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(activeTab == tab ? Color.white.opacity(0.1) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .background(Color.obsidianSurface)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.obsidianBorder),
                alignment: .bottom
            )
            
            // Content Area
            if activeTab == .general {
                GeneralSettingsView(settings: settings)
            } else if activeTab == .privacy {
                PrivacySettingsView(settings: settings)
            } else {
                AboutSettingsView()
            }
        }
        .frame(width: 550, height: 400) // Slightly wider for comfort
        .background(Color.obsidianBackground)
    }
}

// MARK: - Sub Views

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General Settings")
                .font(.custom("Roboto", size: 18))
                .foregroundColor(.luminaTextPrimary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Global Shortcut")
                    .font(.custom("Roboto", size: 14))
                    .foregroundColor(.luminaTextSecondary)
                
                ShortcutRecorder(keyCode: $settings.hotkeyKeyCode, modifiers: $settings.hotkeyModifiers) {
                    // Update hotkey registration when changed
                    let manager = HotKeyManager.shared
                    manager.registerHotKey(keyCode: UInt32(settings.hotkeyKeyCode), modifiers: UInt32(settings.hotkeyModifiers))
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .padding(30)
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
            HStack {
                if isRecording {
                    Text("Type shortcut...")
                        .foregroundColor(.luminaTextSecondary)
                } else {
                    Text(keyString)
                        .foregroundColor(.luminaTextPrimary)
                }
                
                if isRecording {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.luminaTextSecondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(minWidth: 120)
            .background(Color.obsidianSurface)
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
        
        // Very basic mapping for demo purposes. In a real app, use UCKeyTranslate or similar.
        // For now, we handle common keys.
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
        VStack(spacing: 20) {
            Image(systemName: "paperclip")
                .font(.system(size: 48))
                .foregroundColor(.luminaAccent)
                .padding()
                .background(Circle().fill(Color.obsidianSurface).frame(width: 80, height: 80))
            
            Text("Clipy")
                .font(.custom("Roboto", size: 24))
                .fontWeight(.bold)
                .foregroundColor(.luminaTextPrimary)
            
            Text("Version 2.0 (Lumina)")
                .font(.custom("Roboto", size: 13))
                .foregroundColor(.luminaTextSecondary)
            
            Spacer()
        }
        .padding(40)
    }
}

struct PrivacySettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var newAppInput: String = ""
    @State private var newHostInput: String = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Intro Text
                Text("Manage blocked applications and websites. Content copied from these sources will be ignored.")
                    .font(.custom("Roboto", size: 13))
                    .foregroundColor(.luminaTextSecondary)
                
                // Blocked Application Section
                VStack(alignment: .leading, spacing: 10) {
                    Label("Blocked Applications", systemImage: "app.dashed")
                        .font(.custom("Roboto", size: 14))
                        .fontWeight(.medium)
                        .foregroundColor(.luminaTextPrimary)
                    
                    HStack {
                        TextField("e.g. Chrome", text: $newAppInput)
                            .textFieldStyle(.plain)
                            .font(.custom("Roboto", size: 13))
                            .padding(8)
                            .background(Color.obsidianSurface)
                            .cornerRadius(6)
                            .foregroundColor(.luminaTextPrimary)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.obsidianBorder, lineWidth: 0.5))
                        
                        Button(action: addApp) {
                            Image(systemName: "plus")
                                .foregroundColor(.luminaTextPrimary)
                                .padding(8)
                                .background(Color.obsidianSurface)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.obsidianBorder, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .disabled(newAppInput.isEmpty)
                    }
                    
                    LazyVStack(spacing: 2) {
                        ForEach(settings.blockedApps, id: \.self) { app in
                            BlockingRow(label: app, icon: "app.dashed") {
                                removeApp(app)
                            }
                        }
                    }
                    .background(Color.obsidianSurface.opacity(0.3))
                    .cornerRadius(8)
                }
                
                Divider().background(Color.obsidianBorder)
                
                // Blocked Hosts Section
                VStack(alignment: .leading, spacing: 10) {
                    Label("Blocked Websites", systemImage: "globe")
                        .font(.custom("Roboto", size: 14))
                        .fontWeight(.medium)
                        .foregroundColor(.luminaTextPrimary)
                    
                    HStack {
                        TextField("e.g. google.com", text: $newHostInput)
                            .textFieldStyle(.plain)
                            .font(.custom("Roboto", size: 13))
                            .padding(8)
                            .background(Color.obsidianSurface)
                            .cornerRadius(6)
                            .foregroundColor(.luminaTextPrimary)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.obsidianBorder, lineWidth: 0.5))
                        
                        Button(action: addHost) {
                            Image(systemName: "plus")
                                .foregroundColor(.luminaTextPrimary)
                                .padding(8)
                                .background(Color.obsidianSurface)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.obsidianBorder, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .disabled(newHostInput.isEmpty)
                    }
                    
                    LazyVStack(spacing: 2) {
                        ForEach(settings.blockedHosts, id: \.self) { host in
                            BlockingRow(label: host, icon: "globe") {
                                removeHost(host)
                            }
                        }
                    }
                    .background(Color.obsidianSurface.opacity(0.3))
                    .cornerRadius(8)
                }
            }
            .padding(24)
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
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHovering ? Color.white.opacity(0.05) : Color.clear)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
