//
//  ContentView.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI
import AppKit
import Combine

// MARK: - Data Models

enum ClipboardData: Codable, Hashable {
    case text(String, sourceURL: String?)
    case color(String)
}

struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let data: ClipboardData
    let createdAt: Date
    let sourceApp: String?

    var textRepresentation: String {
        switch data {
        case .text(let string, _):
            return string
        case .color(let hex):
            return hex
        }
    }
    
    var smartType: SmartContentType {
        switch data {
        case .color:
            return .color
        case .text(let text, _):
            if let url = URL(string: text), url.scheme != nil, url.host != nil {
                return .url
            }
            // Simple email regex
            let emailPattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
            if text.range(of: emailPattern, options: .regularExpression) != nil {
                return .email
            }
            // Simple code detection (look for common programming keywords or symbols)
            let codeIndicators = ["func ", "var ", "let ", "class ", "struct ", "import ", "{", "}", ";", "def ", "return "]
            if codeIndicators.filter({ text.contains($0) }).count >= 2 {
                return .code
            }
            return .text
        }
    }
    
    func matches(_ query: String) -> Bool {
        let terms = query.lowercased().split(separator: " ")
        guard !terms.isEmpty else { return true }
        
        return terms.allSatisfy { term in
            let termString = String(term)
            
            // 1. Content Match
            if textRepresentation.lowercased().contains(termString) { return true }
            
            // 2. Metadata Match (Source Aapp)
            if let app = sourceApp?.lowercased(), app.contains(termString) { return true }
            
            // 3. Type Match
            if smartType.title.lowercased().contains(termString) { return true }
            
            return false
        }
    }
}

enum SmartContentType {
    case text
    case url
    case email
    case code
    case color
    
    var icon: String {
        switch self {
        case .text: return "doc.text"
        case .url: return "link"
        case .email: return "envelope"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette"
        }
    }
    
    var color: Color {
        switch self {
        case .text: return .luminaTextPrimary
        case .url: return .blue.opacity(0.8)
        case .email: return .orange.opacity(0.8)
        case .code: return .green.opacity(0.8)
        case .color: return .purple.opacity(0.8)
        }
    }
}

// MARK: - Clipboard Manager

@MainActor
class ClipboardManager: ObservableObject {
    @Published var history: [ClipboardItem] = [] {
        didSet {
            // Only save if we are not in a preview environment
            if historyFileURL != nil {
                saveHistory()
            }
        }
    }
    
    private var lastChangeCount = 0
    private var monitoringTask: Task<Void, Error>?
    private let historyFileURL: URL?
    private let settings: AppSettings // Injected settings

    init(settings: AppSettings) {
        self.settings = settings
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectoryURL = appSupportURL.appendingPathComponent("Clipy")

        if !fileManager.fileExists(atPath: appDirectoryURL.path) {
            try? fileManager.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        self.historyFileURL = appDirectoryURL.appendingPathComponent("history.json")
        
        loadHistory()
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    // Private initializer for previews
    private init(history: [ClipboardItem], settings: AppSettings) {
        self.history = history
        self.settings = settings
        self.historyFileURL = nil // Ensure no file operations happen
        self.lastChangeCount = 0
    }

    // Static instance for SwiftUI Previews
    static var preview: ClipboardManager {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let dayBefore = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        
        return ClipboardManager(history: [
            ClipboardItem(id: UUID(), data: .text("Hello from a SwiftUI Preview!", sourceURL: nil), createdAt: Date(), sourceApp: "Xcode"),
            ClipboardItem(id: UUID(), data: .color("#A78BFA"), createdAt: Date(), sourceApp: "Figma"),
            ClipboardItem(id: UUID(), data: .text("This is some sample text that is a bit longer to see how truncation works.", sourceURL: "https://example.com/article"), createdAt: yesterday, sourceApp: "Safari"),
            ClipboardItem(id: UUID(), data: .color("#34D399"), createdAt: yesterday, sourceApp: "Sketch"),
            ClipboardItem(id: UUID(), data: .text("An item from a few days ago.", sourceURL: nil), createdAt: dayBefore, sourceApp: "Mail"),
        ], settings: AppSettings())
    }

    func startMonitoring() {
        // Don't monitor in previews
        guard historyFileURL != nil else { return }

        monitoringTask?.cancel()
        
        monitoringTask = Task {
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(1))
                
                if NSPasteboard.general.changeCount != lastChangeCount {
                    lastChangeCount = NSPasteboard.general.changeCount
                    
                    if let copiedString = NSPasteboard.general.string(forType: .string) {
                        let trimmedString = copiedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if !trimmedString.isEmpty {
                            let newItemData: ClipboardData
                            
                            // 1. Gather Metadata
                            var sourceURL: String? = nil
                            let sourceAppName = NSWorkspace.shared.frontmostApplication?.localizedName
                            
                            if isHexColor(trimmedString) {
                                newItemData = .color(trimmedString)
                            } else {
                                // Check for Chromium source URL
                                if let chromiumURL = NSPasteboard.general.string(forType: NSPasteboard.PasteboardType("org.chromium.source-url")) {
                                    sourceURL = chromiumURL
                                }
                                // Fallback: Check for Web Archive (Safari)
                                else if let webArchiveData = NSPasteboard.general.data(forType: NSPasteboard.PasteboardType("Apple Web Archive pasteboard type")) {
                                    if let plist = try? PropertyListSerialization.propertyList(from: webArchiveData, options: [], format: nil) as? [String: Any],
                                       let mainResource = plist["WebMainResource"] as? [String: Any],
                                       let urlString = mainResource["WebResourceURL"] as? String {
                                        sourceURL = urlString
                                    }
                                }
                                
                                newItemData = .text(trimmedString, sourceURL: sourceURL)
                            }
                            
                            // 2. CHECK PRIVACY SETTINGS
                            let host = sourceURL != nil ? URL(string: sourceURL!)?.host : nil
                            if settings.isBlocked(app: sourceAppName, host: host) {
                                print("Blocked by privacy settings: App=\(sourceAppName ?? "nil") Host=\(host ?? "nil")")
                                continue 
                            }
                            
                            history.removeAll { $0.data == newItemData }
                            
                            let newItem = ClipboardItem(
                                id: UUID(),
                                data: newItemData,
                                createdAt: Date(),
                                sourceApp: sourceAppName
                            )
                            history.insert(newItem, at: 0)
                        }
                    }
                }
            }
        }
    }
    
    private func isHexColor(_ string: String) -> Bool {
        let pattern = "^#?([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$"
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.firstMatch(in: string, options: [], range: NSRange(location: 0, length: string.utf16.count)) != nil
    }
    
    func copyToPasteboard(item: ClipboardItem) {
        NSPasteboard.general.clearContents()
        switch item.data {
        case .text(let string, _):
            NSPasteboard.general.setString(string, forType: .string)
        case .color(let hex):
            NSPasteboard.general.setString(hex, forType: .string)
        }
    }
    
    private func loadHistory() {
        guard let historyFileURL, let data = try? Data(contentsOf: historyFileURL) else { return }
        do {
            let decoder = JSONDecoder()
            history = try decoder.decode([ClipboardItem].self, from: data)
        } catch {
            print("Failed to load clipboard history: \(error.localizedDescription)")
        }
    }
    
    private func saveHistory() {
        guard let historyFileURL else { return }
        Task(priority: .background) {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(history)
                try data.write(to: historyFileURL, options: .atomic)
            } catch {
                print("Failed to save clipboard history: \(error.localizedDescription)")
            }
        }
    }
    
    deinit {
        monitoringTask?.cancel()
    }
}

// MARK: - SwiftUI Views

struct ContentView: View {
    @ObservedObject var appSettings: AppSettings
    @StateObject private var clipboardManager: ClipboardManager
    @State private var selectedItemID: ClipboardItem.ID?
    @State private var searchText = ""
    
    init(settings: AppSettings) {
        self.appSettings = settings
        _clipboardManager = StateObject(wrappedValue: ClipboardManager(settings: settings))
    }

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Sidebar (Timeline)
            timelineView
                .frame(width: 320)
                .background(Color.obsidianBackground)
            
            // MARK: - Detail Stage
            ZStack {
                Color.obsidianBackground.ignoresSafeArea()
                
                if let selectedItem {
                    LuminaDetailStage(item: selectedItem)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(VisualEffectView().ignoresSafeArea())
        .ignoresSafeArea()
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.obsidianBorder, lineWidth: 1)
                .ignoresSafeArea()
        )
        .task {
            clipboardManager.startMonitoring()
        }
    }
    
    // MARK: - Timeline View
    private var timelineView: some View {
        VStack(spacing: 0) {
            // Search Area
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.luminaTextSecondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.custom("Roboto", size: 14))
                        .fontWeight(.medium)
                        .foregroundColor(.luminaTextPrimary)
                }
                .padding(8)
                .background(Color.obsidianSurface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.obsidianBorder, lineWidth: 0.5)
                )
                
                // Settings Toggle removed as per request
            }
            .padding(16)
            .background(Color.obsidianSurface.opacity(0.5))
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredHistory) { item in
                            LuminaRow(item: item, isSelected: selectedItemID == item.id)
                                .id(item.id) // Important for ScrollViewReader
                                .onTapGesture {
                                    selectedItemID = item.id
                                }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
                .background(
                    // Hidden keyboard shortcuts
                    ZStack {
                        Button("") { moveSelection(offset: -1, proxy: proxy) }
                            .keyboardShortcut(.upArrow, modifiers: [])
                        Button("") { moveSelection(offset: 1, proxy: proxy) }
                            .keyboardShortcut(.downArrow, modifiers: [])
                    }
                    .frame(width: 0, height: 0)
                    .opacity(0)
                )
            }
        }
    }
    
    private var filteredHistory: [ClipboardItem] {
        if searchText.isEmpty {
            return clipboardManager.history
        } else {
            return clipboardManager.history.filter { $0.matches(searchText) }
        }
    }
    
    private func moveSelection(offset: Int, proxy: ScrollViewProxy) {
        let history = filteredHistory // Use filtered history for navigation
        guard !history.isEmpty else { return }
        
        let currentIndex = history.firstIndex { $0.id == selectedItemID } ?? -1
        var newIndex = currentIndex + offset
        
        // Clamp selection
        newIndex = max(0, min(newIndex, history.count - 1))
        
        // Handling separate case for initial selection from "none" if needed, 
        // but the clamping above handles typical -1 + 1 = 0 scenario for Down arrow.
        // For Up arrow from -1 (-2), it clamps to 0. So first press selects top item.
        
        let newItem = history[newIndex]
        if selectedItemID != newItem.id {
            selectedItemID = newItem.id
            withAnimation {
                proxy.scrollTo(newItem.id, anchor: .center)
            }
        }
    }
    
    private var selectedItem: ClipboardItem? {
        // Look up in full history to ensure detail view works even if search changes temporarily
        clipboardManager.history.first { $0.id == selectedItemID }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.luminaTextSecondary.opacity(0.5))
            Text("Select a clip to illuminate")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(.luminaTextSecondary)
        }
    }
}

// MARK: - Supporting Views

struct LuminaRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.smartType.icon)
                .font(.system(size: 14)) // Icons keep system font usually, or specific icon font
                .foregroundColor(isSelected ? .luminaTextPrimary : .luminaTextSecondary)
                .frame(width: 20, height: 20)
            
            Text(item.textRepresentation)
                .font(.custom("Roboto", size: 13))
                .fontWeight(.regular)
                .foregroundColor(isSelected ? .luminaTextPrimary : .luminaTextSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                
                // Metadata removed as per user request
            Spacer() // Force left alignment
        }
        .padding(.horizontal, 6) // Tighter inner padding to reduce right space
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.15) : (isHovering ? Color.obsidianSurface.opacity(0.5) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                 .stroke(isSelected ? Color.white.opacity(0.2) : Color.clear, lineWidth: 0.5)
        )
        .padding(.leading, 12) // Added left margin
        .padding(.trailing, 4) // Reduced trailing to maintain balance
        .onHover { hovering in
            isHovering = hovering // No animation
        }
        .contentShape(Rectangle()) // Ensure entire row is clickable, including transparent areas
    }
    
    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.createdAt, relativeTo: Date())
    }
}

struct LuminaDetailStage: View {
    let item: ClipboardItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Adaptive Header
            HStack {
                Image(systemName: item.smartType.icon)
                    .font(.system(size: 24))
                    .foregroundColor(item.smartType.color)
                Text(item.smartType.title)
                    .font(.custom("Roboto", size: 24))
                    .fontWeight(.light) // Roboto doesn't have UltraLight usually, switching to Light or Thin, sticking to Light for safety
                    .foregroundColor(.luminaTextPrimary)
                Spacer()
            }
            .padding(.bottom, 20)
            
            // Content
            ScrollView {
                Text(item.textRepresentation)
                    .font(item.smartType == .code ? .system(size: 13, design: .monospaced) : .custom("Roboto", size: 14))
                    .foregroundColor(.luminaTextPrimary)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer()
            
            // Metadata Panel
            // Metadata Panel
            VStack(alignment: .leading, spacing: 5) {
                Text("Metadata")
                   .font(.custom("Roboto", size: 12))
                   .fontWeight(.bold)
                   .foregroundColor(.luminaTextSecondary)
                   .padding(.horizontal, 16)
                   .padding(.bottom, 5)

                VStack(spacing: 0) {
                    if let source = item.sourceApp {
                        MetadataRow(icon: "app.dashed", label: "Source", value: source)
                    }
                    
                    if case .text(let text, let sourceURL) = item.data {
                        // Show source URL if available
                        if let url = sourceURL, let host = URL(string: url)?.host {
                            MetadataRow(icon: "link", label: "URL", value: host)
                        }
                        
                        let byteCount = text.utf8.count
                        let sizeString = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
                        MetadataRow(icon: "arrow.up.left.and.arrow.down.right", label: "Size", value: sizeString)
                    }
                    
                    MetadataRow(icon: "calendar", label: "Date", value: item.createdAt.formatted(date: .numeric, time: .shortened))
                    MetadataRow(icon: "folder", label: "Type", value: item.smartType.title)
                }
                .padding(.vertical, 8)
                .background(Color.obsidianSurface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.obsidianBorder, lineWidth: 0.5)
                )
            }
        }
        .padding(24)
        .background(Color.clear) // Removed gradient as per user request
    }
}

struct MetadataRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 0) { // Zero spacing, controlled by frame/padding
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.luminaTextSecondary)
                .frame(width: 16)
                .padding(.trailing, 8)
                
            Text(label)
                .font(.custom("Roboto", size: 13))
                .foregroundColor(.luminaTextSecondary)
                .frame(width: 50, alignment: .leading) // Fixed width for alignment
                
            Text(value)
                .font(.custom("Roboto", size: 13))
                .fontWeight(.medium)
                .foregroundColor(.luminaTextPrimary)
                
            Spacer() // Push everything to left? Or just let it sit? User said "close to their type". 
            // If I put Spacer() at the end, the whole block is left aligned in the container.
            // The container is a VStack(alignment: .leading). So simply removing the middle spacer is enough.
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4) // Tighter vertical padding for "list" feel
    }
}

extension SmartContentType {
    var title: String {
        switch self {
        case .text: return "Text"
        case .url: return "Link"
        case .code: return "Code"
        case .email: return "Contact"
        case .color: return "Color"
        }
    }
}

// MARK: - Preview

// #Preview {
//     ContentView()
//         .frame(width: 800, height: 600)
// }
