
import SwiftUI
import Combine

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
    
    init() {
        self.blockedApps = AppSettings.load(key: "blockedApps")
        self.blockedHosts = AppSettings.load(key: "blockedHosts")
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
                GeneralSettingsView()
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
    var body: some View {
        VStack(spacing: 20) {
            Text("General Settings")
                .font(.custom("Roboto", size: 18))
                .foregroundColor(.luminaTextPrimary)
            
            Text("Launch at Login, Shortcuts, and History retention settings will go here.")
                .font(.custom("Roboto", size: 13))
                .foregroundColor(.luminaTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding(30)
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
