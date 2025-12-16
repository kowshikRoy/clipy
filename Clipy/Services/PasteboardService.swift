//
//  PasteboardService.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import AppKit
import Combine
import CryptoKit

class PasteboardService: ObservableObject {
    @Published var newItem: ClipboardItem?
    
    private var lastChangeCount = 0
    private var monitoringTask: Task<Void, Error>?
    private let settings: AppSettings
    
    init(settings: AppSettings) {
        self.settings = settings
        self.lastChangeCount = NSPasteboard.general.changeCount
    }
    
    func startMonitoring() {
        monitoringTask?.cancel()
        
        monitoringTask = Task {
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(1)) // Poll every 1 second
                
                let currentChangeCount = NSPasteboard.general.changeCount
                if currentChangeCount != lastChangeCount {
                    lastChangeCount = currentChangeCount
                    await checkForNewItem()
                }
            }
        }
    }
    
    func stopMonitoring() {
        monitoringTask?.cancel()
    }
    
    @MainActor
    private func checkForNewItem() {
        // Check pasteboard types to determine if it's an image
        let types = NSPasteboard.general.types ?? []
        let hasImageType = types.contains(NSPasteboard.PasteboardType.tiff) ||
                          types.contains(NSPasteboard.PasteboardType.png) ||
                          types.contains(NSPasteboard.PasteboardType("public.jpeg")) ||
                          types.contains(NSPasteboard.PasteboardType("public.image"))
        
        // Check for Image FIRST
        if hasImageType, let image = NSImage(pasteboard: NSPasteboard.general) {
            handleImage(image)
        } else if let copiedString = NSPasteboard.general.string(forType: .string) {
            handleText(copiedString)
        }
    }
    
    private func handleImage(_ image: NSImage) {
        // Convert to PNG data
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
            
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
                return
            }
            
            let item = ClipboardItem(
                id: UUID(),
                data: newItemData,
                createdAt: Date(),
                sourceApp: sourceAppName
            )
            
            DispatchQueue.main.async {
                self.newItem = item
            }
        }
    }
    
    private func handleText(_ text: String) {
        let trimmedString = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedString.isEmpty else { return }
        
        var newItemData: ClipboardData
        
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
            return
        }
        
        let item = ClipboardItem(
            id: UUID(),
            data: newItemData,
            createdAt: Date(),
            sourceApp: sourceAppName
        )
        
        DispatchQueue.main.async {
            self.newItem = item
        }
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

    private func isHexColor(_ string: String) -> Bool {
        let pattern = "^#?([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$"
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.firstMatch(in: string, options: [], range: NSRange(location: 0, length: string.utf16.count)) != nil
    }
}
