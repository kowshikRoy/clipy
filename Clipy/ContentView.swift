//
//  ContentView.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI
import AppKit
import Carbon
import Combine
import CryptoKit
import ApplicationServices



// MARK: - Data Models

enum ClipboardData: Codable, Hashable {
    case text(String, sourceURL: String?)
    case color(String)
    case image(String) // Path to image file relative to app support dir
}

struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let data: ClipboardData
    let createdAt: Date
    let sourceApp: String?
    var isPinned: Bool = false
    var copyCount: Int = 1
    var customMetadata: String? = nil

    var textRepresentation: String {
        switch data {
        case .text(let string, _):
            return string
        case .color(let hex):
            return hex
        case .image:
            return "Image"
        }
    }
    
    var smartType: SmartContentType {
        switch data {
        case .color:
            return .color
        case .image:
            return .image
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
    case image

    
    var icon: String {
        switch self {
        case .text: return "doc.text"
        case .url: return "link"
        case .email: return "envelope"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette"
        case .image: return "photo"
        }
    }
    
    var color: Color {
        switch self {
        case .text: return .luminaTextPrimary
        case .url: return .blue.opacity(0.8)
        case .email: return .orange.opacity(0.8)
        case .code: return .green.opacity(0.8)
        case .color: return .purple.opacity(0.8)
        case .image: return .pink.opacity(0.8)
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
        
        let imagesDirectoryURL = appDirectoryURL.appendingPathComponent("images")
        if !fileManager.fileExists(atPath: imagesDirectoryURL.path) {
            try? fileManager.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }
        
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
                    
                    // Check pasteboard types to determine if it's an image
                    let types = NSPasteboard.general.types ?? []
                    let hasImageType = types.contains(NSPasteboard.PasteboardType.tiff) ||
                                      types.contains(NSPasteboard.PasteboardType.png) ||
                                      types.contains(NSPasteboard.PasteboardType("public.jpeg")) ||
                                      types.contains(NSPasteboard.PasteboardType("public.image"))
                    
                    // Check for Image FIRST (websites often put both image and text on pasteboard)
                    // But ONLY if there's actually an image type in the pasteboard
                    if hasImageType, let image = NSImage(pasteboard: NSPasteboard.general) {
                        // Convert to PNG data
                        if let tiffData = image.tiffRepresentation,
                           let bitmap = NSBitmapImageRep(data: tiffData),
                           let pngData = bitmap.representation(using: .png, properties: [:]) {
                            
                            // Use SHA256 hash of image data as filename for deduplication
                            let hashData = SHA256.hash(data: pngData)
                            let hashString = hashData.compactMap { String(format: "%02x", $0) }.joined()
                            let filename = "images/\(hashString).png"
                            
                            if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                                let fileURL = appSupportURL.appendingPathComponent("Clipy").appendingPathComponent(filename)
                                
                                // Only write if file doesn't exist (deduplication)
                                if !FileManager.default.fileExists(atPath: fileURL.path) {
                                    try? pngData.write(to: fileURL)
                                }
                                
                                let newItemData = ClipboardData.image(filename)
                                let sourceAppName = NSWorkspace.shared.frontmostApplication?.localizedName
                                
                                // Privacy check for image (app name only)
                                if settings.isBlocked(app: sourceAppName, host: nil) {
                                    continue
                                }
                                
                                // Check for existing item to increment count
                                var existingCount = 1
                                if let existing = history.first(where: { $0.data == newItemData }) {
                                    existingCount = existing.copyCount + 1
                                }
                                
                                // Remove existing duplicate
                                history.removeAll { $0.data == newItemData }
                                
                                let newItem = ClipboardItem(
                                    id: UUID(),
                                    data: newItemData,
                                    createdAt: Date(),
                                    sourceApp: sourceAppName,
                                    copyCount: existingCount
                                )
                                history.insert(newItem, at: 0)
                            }
                        }

                    } else if let copiedString = NSPasteboard.general.string(forType: .string) {

                        // Only check for text if no image was found
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
                            
                            // Check for existing item to increment count
                            var existingCount = 1
                            if let existing = history.first(where: { $0.data == newItemData }) {
                                existingCount = existing.copyCount + 1
                            }
                            
                            history.removeAll { $0.data == newItemData }
                            
                            let newItem = ClipboardItem(
                                id: UUID(),
                                data: newItemData,
                                createdAt: Date(),
                                sourceApp: sourceAppName,
                                copyCount: existingCount
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
        case .image(let filename):
            if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let fileURL = appSupportURL.appendingPathComponent("Clipy").appendingPathComponent(filename)
                if let image = NSImage(contentsOf: fileURL) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                }
            }
        }
    }
    
    func togglePin(for itemID: UUID) {
        guard let index = history.firstIndex(where: { $0.id == itemID }) else { return }
        history[index].isPinned.toggle()
    }
    
    func updateItem(id: UUID, newText: String) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        var item = history[index]
        // Currently only supporting updating text content
        if case .text(_, let sourceURL) = item.data {
            item = ClipboardItem(id: item.id, data: .text(newText, sourceURL: sourceURL), createdAt: item.createdAt, sourceApp: item.sourceApp, isPinned: item.isPinned, copyCount: item.copyCount, customMetadata: item.customMetadata)
             history[index] = item
        }
    }

    func updateItemMetadata(id: UUID, metadata: String?) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        var item = history[index]
        item.customMetadata = metadata
        history[index] = item
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
    @ObservedObject var focusManager: AppFocusManager
    @StateObject private var clipboardManager: ClipboardManager
    @State private var selectedItemID: ClipboardItem.ID?
    @State private var searchText = ""
    @State private var isEditing = false
    @State private var editingText = ""
    
    // Metadata State
    @State private var isAddingMetadata = false
    @State private var metadataInput = ""

    init(settings: AppSettings, focusManager: AppFocusManager) {
        self.appSettings = settings
        self.focusManager = focusManager
        _clipboardManager = StateObject(wrappedValue: ClipboardManager(settings: settings))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
            // MARK: - Sidebar (Timeline)
            timelineView
                .frame(width: 320)
                .background(Color.obsidianBackground.opacity(0.6))
            
            Rectangle()
                .fill(Color.obsidianBorder)
                .frame(width: 1)
                .ignoresSafeArea(edges: .vertical)
            
            // MARK: - Detail Stage
            ZStack {
                Color.obsidianBackground.opacity(0.6).ignoresSafeArea()
                
                if let selectedItem {
                    LuminaDetailStage(
                        item: selectedItem,
                        isEditing: $isEditing,
                        editingText: $editingText,
                        onSave: saveEdit,
                        onCancel: cancelEdit
                    )
                } else {
                    emptyState
                }

                // Metadata Input Overlay
                if isAddingMetadata {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            isAddingMetadata = false
                        }

                    VStack(spacing: 16) {
                        Text("Add Metadata")
                            .font(.custom("Roboto", size: 16))
                            .fontWeight(.bold)
                            .foregroundColor(.luminaTextPrimary)

                        TextField("Enter metadata...", text: $metadataInput)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color.obsidianSurface)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.obsidianBorder, lineWidth: 1)
                            )
                            .foregroundColor(.luminaTextPrimary)
                            .frame(width: 250)
                            .onSubmit {
                                saveMetadata()
                            }

                        HStack(spacing: 12) {
                            Button("Cancel") {
                                isAddingMetadata = false
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.luminaTextSecondary)

                            Button("Save") {
                                saveMetadata()
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor)
                            .cornerRadius(6)
                        }
                    }
                    .padding(24)
                    .background(Color.obsidianBackground)
                    .cornerRadius(12)
                    .shadow(radius: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.obsidianBorder, lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        
        FooterView(
            focusManager: focusManager,
            onPasteToApp: pasteToApp,
            onCopyToClipboard: copyToClipboard,
            onEdit: editEntry,
            onPin: pinEntry,
            onAddMetadata: addMetadata,
            onDelete: deleteEntry,
            onDeleteAll: deleteAllEntries
        )
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
            ensureSelection()
        }
        .onChange(of: clipboardManager.history) { _ in ensureSelection() }
        .onChange(of: searchText) { _ in ensureSelection() }
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
                        .onSubmit {
                            pasteToApp()
                        }
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
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        // Pinned Section
                        if !pinnedItems.isEmpty {
                            Section(header: sectionHeader(title: "Pinned", icon: "pin.fill")) {
                                ForEach(pinnedItems) { item in
                                    LuminaRow(item: item, isSelected: selectedItemID == item.id)
                                        .id(item.id)
                                        .onTapGesture {
                                            selectedItemID = item.id
                                        }
                                }
                            }
                        }
                        
                        // Recent Section
                        if !recentItems.isEmpty {
                            Section(header: sectionHeader(title: "Recent", icon: "clock")) {
                                ForEach(recentItems) { item in
                                    LuminaRow(item: item, isSelected: selectedItemID == item.id)
                                        .id(item.id)
                                        .onTapGesture {
                                            selectedItemID = item.id
                                        }
                                }
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
                        Button("") { NSApplication.shared.hide(nil) }
                            .keyboardShortcut(.cancelAction)
                    }
                    .frame(width: 0, height: 0)
                    .opacity(0)
                )
            }
        }
    }
    
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.luminaTextSecondary)
            Text(title.uppercased())
                .font(.custom("Roboto", size: 11))
                .fontWeight(.bold)
                .foregroundColor(.luminaTextSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.clear)
    }
    
    private var pinnedItems: [ClipboardItem] {
        filteredHistory.filter { $0.isPinned }
    }
    
    private var recentItems: [ClipboardItem] {
        filteredHistory.filter { !$0.isPinned }
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
            isEditing = false // Exit editing mode when selection changes
            withAnimation {
                proxy.scrollTo(newItem.id, anchor: .center)
            }
        }
    }
    
    private var selectedItem: ClipboardItem? {
        // Look up in full history to ensure detail view works even if search changes temporarily
        clipboardManager.history.first { $0.id == selectedItemID }
    }
    
    private func ensureSelection() {
        if let selectedItemID, filteredHistory.contains(where: { $0.id == selectedItemID }) {
            return
        }

        if let firstItem = filteredHistory.first {
            selectedItemID = firstItem.id
        } else {
            selectedItemID = nil
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.luminaTextSecondary.opacity(0.5))
            Text("No clips found")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(.luminaTextSecondary)
        }
    }

    
    // MARK: - Actions
    
    private func pasteToApp() {
        let itemToPaste: ClipboardItem?
        
        if let selectedItemID, let item = clipboardManager.history.first(where: { $0.id == selectedItemID }) {
            itemToPaste = item
        } else if let firstItem = filteredHistory.first {
            itemToPaste = firstItem
        } else {
            itemToPaste = nil
        }
        
        guard let item = itemToPaste else { return }
        // 1. Copy to pasteboard
        clipboardManager.copyToPasteboard(item: item)
        // 2. Switch Focus Explicitly
        if let previousApp = focusManager.previousApp {
            previousApp.activate(options: .activateIgnoringOtherApps)
        } else {
            NSApplication.shared.hide(nil)
        }
        // 3. Simulate Cmd+V
        simulatePaste()
    }
    
    private func simulatePaste() {
        // Check for accessibility permissions first
        guard checkAccessibilityPermissions() else {
            showPermissionError()
            return
        }
        
        // Reduced delay from 0.3s to 0.1s for faster paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .hidSystemState)
            
            let vKeyCode: CGKeyCode = 9 // 9 is 'v'
            
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
            keyDown?.flags = .maskCommand
            
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
            keyUp?.flags = .maskCommand
            
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
    
    private func checkAccessibilityPermissions() -> Bool {
        // Check if the app is trusted for accessibility
        let trusted = AXIsProcessTrusted()
        return trusted
    }
    
    private func showPermissionError() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
Clipy needs Accessibility permission to paste into other apps.

How to enable:
1. Open System Settings
2. Go to Privacy & Security → Accessibility
3. Find and enable "Clipy" in the list
4. Restart Clipy

Alternatively, you can use Cmd+V manually after copying.
"""
        alert.alertStyle = .warning

        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open System Settings to Privacy & Security > Accessibility
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func copyToClipboard() {
        guard let selectedItemID, let item = clipboardManager.history.first(where: { $0.id == selectedItemID }) else { return }
        clipboardManager.copyToPasteboard(item: item)
        // Show toast or slight feedback?
    }
    
    private func editEntry() {
        guard let selectedItemID, let item = clipboardManager.history.first(where: { $0.id == selectedItemID }) else { return }
        if case .text(let text, _) = item.data {
            editingText = text
            isEditing = true
        }
    }

    private func saveEdit() {
        guard let selectedItemID else { return }
        clipboardManager.updateItem(id: selectedItemID, newText: editingText)
        isEditing = false
    }

    private func cancelEdit() {
        isEditing = false
    }
    
    private func pinEntry() {
        guard let selectedItemID else { return }
        clipboardManager.togglePin(for: selectedItemID)
    }

    private func addMetadata() {
        guard let selectedItemID, let item = clipboardManager.history.first(where: { $0.id == selectedItemID }) else { return }
        metadataInput = item.customMetadata ?? ""
        isAddingMetadata = true
    }

    private func saveMetadata() {
        guard let selectedItemID else { return }
        clipboardManager.updateItemMetadata(id: selectedItemID, metadata: metadataInput.isEmpty ? nil : metadataInput)
        isAddingMetadata = false
    }
    
    private func deleteEntry() {
        guard let selectedItemID else { return }

        let history = filteredHistory
        var nextID: UUID?

        if let index = history.firstIndex(where: { $0.id == selectedItemID }) {
            if index + 1 < history.count {
                nextID = history[index + 1].id
            } else if index - 1 >= 0 {
                nextID = history[index - 1].id
            }
        }

        if let item = clipboardManager.history.first(where: { $0.id == selectedItemID }) {
            deleteImageFileIfNeeded(item: item)
        }
        clipboardManager.history.removeAll { $0.id == selectedItemID }
        self.selectedItemID = nextID
    }
    
    private func deleteAllEntries() {
        // Delete all image files
        for item in clipboardManager.history {
            deleteImageFileIfNeeded(item: item)
        }
        clipboardManager.history.removeAll()
        selectedItemID = nil
    }
    
    private func deleteImageFileIfNeeded(item: ClipboardItem) {
        if case .image(let filename) = item.data {
            if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let fileURL = appSupportURL.appendingPathComponent("Clipy").appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: fileURL)
            }
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
            // Show thumbnail for images
            if case .image(let filename) = item.data {
                if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    let fileURL = appSupportURL.appendingPathComponent("Clipy").appendingPathComponent(filename)
                    if let nsImage = NSImage(contentsOf: fileURL) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: item.smartType.icon)
                            .font(.system(size: 14))
                            .foregroundColor(isSelected ? .luminaTextPrimary : .luminaTextSecondary)
                            .frame(width: 20, height: 20)
                    }
                } else {
                    Image(systemName: item.smartType.icon)
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .luminaTextPrimary : .luminaTextSecondary)
                        .frame(width: 20, height: 20)
                }
            } else {
                Image(systemName: item.smartType.icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .luminaTextPrimary : .luminaTextSecondary)
                    .frame(width: 20, height: 20)
            }
            
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
                .fill(isSelected ? Color.white.opacity(0.15) : (isHovering ? Color.white.opacity(0.08) : Color.clear))
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
    @Binding var isEditing: Bool
    @Binding var editingText: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Adaptive Header
            HStack {
                Image(systemName: item.smartType.icon)
                    .font(.system(size: 24))
                    .foregroundColor(item.smartType.color)
                    .foregroundColor(item.smartType.color)
                
                Text(item.smartType.title)
                    .font(.custom("Roboto", size: 24))
                    .fontWeight(.light)
                    .foregroundColor(.luminaTextPrimary)
                
                Spacer()
                
                if isEditing {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.plain)
                        .foregroundColor(.luminaTextSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                    
                    Button("Save", action: onSave)
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                }
            }
            .padding(.bottom, 20)
            
            // Content
            // Content
            if isEditing {
                TextEditor(text: $editingText)
                    .font(.custom("Roboto", size: 14))
                    .foregroundColor(.luminaTextPrimary)
                    .padding(4) // Match read-only padding roughly
                    .scrollContentBackground(.hidden) // Remove default background
                    .background(Color.clear) // Clear background
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1) // Subtle focus ring
                    )
            } else {
                // Display image or text
                if case .image(let filename) = item.data {
                    if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                        let fileURL = appSupportURL.appendingPathComponent("Clipy").appendingPathComponent(filename)
                        if let nsImage = NSImage(contentsOf: fileURL) {
                            GeometryReader { geometry in
                                ScrollView([.horizontal, .vertical]) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                                        .cornerRadius(8)
                                }
                            }
                        } else {
                            Text("Image not found")
                                .foregroundColor(.luminaTextSecondary)
                        }
                    } else {
                        Text("Error loading image")
                            .foregroundColor(.luminaTextSecondary)
                    }

                } else {
                    ScrollView {
                        Text(item.textRepresentation)
                            .font(item.smartType == .code ? .system(size: 13, design: .monospaced) : .custom("Roboto", size: 14))
                            .foregroundColor(.luminaTextPrimary)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
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
                        MetadataRow(icon: "app.dashed", label: "Source", value: source, appIcon: iconForApp(source))
                    }

                    if let metadata = item.customMetadata {
                        MetadataRow(icon: "tag", label: "Note", value: metadata)
                    }
                    
                    if item.copyCount > 1 {
                        MetadataRow(icon: "doc.on.doc", label: "Copied", value: "\(item.copyCount) times")
                    } else {
                        MetadataRow(icon: "doc.on.doc", label: "Copied", value: "1 time")
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
                    
                    if case .image(let filename) = item.data {
                        // Show image dimensions
                        if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                            let fileURL = appSupportURL.appendingPathComponent("Clipy").appendingPathComponent(filename)
                            if let nsImage = NSImage(contentsOf: fileURL) {
                                let width = Int(nsImage.size.width)
                                let height = Int(nsImage.size.height)
                                MetadataRow(icon: "arrow.up.left.and.arrow.down.right", label: "Size", value: "\(width) × \(height)")
                            }
                        }
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
    
    private func iconForApp(_ name: String) -> NSImage? {
        // 1. Try exact path in /Applications
        let path = "/Applications/\(name).app"
        if FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        
        // 2. Try in /System/Applications
        let systemPath = "/System/Applications/\(name).app"
        if FileManager.default.fileExists(atPath: systemPath) {
            return NSWorkspace.shared.icon(forFile: systemPath)
        }
        
        // 3. Try to use NSWorkspace to find app by name (more expensive/complex generally, simply fallback for MVP)
        // If we had the bundle identifier it would be easier.
        
        return nil
    }
}

struct MetadataRow: View {
    let icon: String
    let label: String
    let value: String
    var appIcon: NSImage? = nil
    
    var body: some View {
        HStack(spacing: 0) { // Zero spacing, controlled by frame/padding
            if let appIcon = appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .padding(.trailing, 8)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.luminaTextSecondary)
                    .frame(width: 16)
                    .padding(.trailing, 8)
            }
                
            Text(label)
                .font(.custom("Roboto", size: 13))
                .foregroundColor(.luminaTextSecondary)
                .frame(width: 50, alignment: .leading) // Fixed width for alignment
                
            Text(value)
                .font(.custom("Roboto", size: 13))
                .fontWeight(.medium)
                .foregroundColor(.luminaTextPrimary)
                
            Spacer() 
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
        case .image: return "Image"
        }
    }
}

// MARK: - Preview

// #Preview {
//     ContentView()
//         .frame(width: 800, height: 600)
// }
