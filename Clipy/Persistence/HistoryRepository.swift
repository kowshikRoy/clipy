//
//  HistoryRepository.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import Foundation

actor HistoryRepository {
    private let historyFileURL: URL?
    
    init() {
        let fileManager = FileManager.default
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appDirectoryURL = appSupportURL.appendingPathComponent("Clipy")
            
            if !fileManager.fileExists(atPath: appDirectoryURL.path) {
                try? fileManager.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            }
            
            self.historyFileURL = appDirectoryURL.appendingPathComponent("history.json")
            
            let imagesDirectoryURL = appDirectoryURL.appendingPathComponent("images")
            if !fileManager.fileExists(atPath: imagesDirectoryURL.path) {
                try? fileManager.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            }
        } else {
            self.historyFileURL = nil
        }
    }
    
    func load() -> [ClipboardItem] {
        guard let historyFileURL, let data = try? Data(contentsOf: historyFileURL) else { return [] }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode([ClipboardItem].self, from: data)
        } catch {
            print("Failed to load clipboard history: \(error.localizedDescription)")
            return []
        }
    }
    
    private var saveTask: Task<Void, Error>?
    
    func save(_ items: [ClipboardItem]) {
        saveTask?.cancel()
        
        saveTask = Task {
            // Debounce for 2 seconds
            try await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            
            guard let historyFileURL else { return }
            
            // Perform Save
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(items)
            try data.write(to: historyFileURL, options: .atomic)
        }
    }
    
    func deleteImage(_ filename: String) {
        let fileManager = FileManager.default
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let fileURL = appSupportURL.appendingPathComponent("Clipy").appendingPathComponent(filename)
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
