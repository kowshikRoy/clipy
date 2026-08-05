//
//  HistoryRepository.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import Foundation
import SQLite3
import CryptoKit

actor HistoryRepository {
    private let dbManager = DatabaseManager.shared
    
    init() {
        // Ensure image directory exists
        let fileManager = FileManager.default
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
             let imagesDirectoryURL = appSupportURL.appendingPathComponent("Clipy").appendingPathComponent("images")
             if !fileManager.fileExists(atPath: imagesDirectoryURL.path) {
                 try? fileManager.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true, attributes: nil)
             }
         }
        
        migrateFromJSON()
    }
    
    private func migrateFromJSON() {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let historyFileURL = appSupportURL.appendingPathComponent("Clipy").appendingPathComponent("history.json")
        
        guard fileManager.fileExists(atPath: historyFileURL.path),
              let data = try? Data(contentsOf: historyFileURL) else { return }
              
        print("Migrating from JSON to SQL...")
        do {
            let decoder = JSONDecoder()
            let items = try decoder.decode([ClipboardItem].self, from: data)
            
            for item in items.reversed() { // Insert oldest first to keep order
                insert(item)
            }
            
            // Rename JSON to backup
            let backupURL = historyFileURL.deletingPathExtension().appendingPathExtension("json.bak")
            try? fileManager.removeItem(at: backupURL)
            try fileManager.moveItem(at: historyFileURL, to: backupURL)
            print("Migration complete. Backup created at \(backupURL.path)")
        } catch {
            print("Migration failed: \(error)")
        }
    }

    func load(limit: Int = 1000) -> [ClipboardItem] {
        var items: [ClipboardItem] = []
        let sql = "SELECT * FROM clipboard_items ORDER BY created_at DESC LIMIT \(limit)"
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(dbManager.getDB(), sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let item = parseItem(from: statement) {
                    items.append(item)
                }
            }
        }
        sqlite3_finalize(statement)
        return items
    }
    
    func search(query: String) -> [ClipboardItem] {
         var items: [ClipboardItem] = []
         let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
         guard !trimmedQuery.isEmpty else { return items }
         
         // Check for explicit tag search prefix (#tag, tag:tag, note:tag)
         var tagFilter: String? = nil
         let lower = trimmedQuery.lowercased()
         if lower.hasPrefix("#") {
             let term = String(trimmedQuery.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
             if !term.isEmpty { tagFilter = term }
         } else if lower.hasPrefix("tag:") {
             let term = String(trimmedQuery.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
             if !term.isEmpty { tagFilter = term }
         } else if lower.hasPrefix("note:") {
             let term = String(trimmedQuery.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
             if !term.isEmpty { tagFilter = term }
         }
         
         let sql: String
         let ftsQuery: String
         let likeQuery: String
         
         if let tag = tagFilter {
             sql = """
             SELECT * FROM clipboard_items 
             WHERE custom_metadata LIKE ?
             ORDER BY created_at DESC LIMIT 500
             """
             likeQuery = "%\(tag)%"
             var statement: OpaquePointer?
             if sqlite3_prepare_v2(dbManager.getDB(), sql, -1, &statement, nil) == SQLITE_OK {
                 sqlite3_bind_text(statement, 1, (likeQuery as NSString).utf8String, -1, nil)
                 while sqlite3_step(statement) == SQLITE_ROW {
                     if let item = parseItem(from: statement) {
                         items.append(item)
                     }
                 }
             } else {
                 print("Tag Search prepare failed")
             }
             sqlite3_finalize(statement)
             return items
         }
         
         let sanitizedForFTS = trimmedQuery.replacingOccurrences(of: "\"", with: " ")
         ftsQuery = "\"\(sanitizedForFTS)\"* OR \"\(sanitizedForFTS)\""
         likeQuery = "%\(trimmedQuery)%"
         
         sql = """
         SELECT * FROM clipboard_items 
         WHERE rowid IN (SELECT rowid FROM clipboard_search WHERE clipboard_search MATCH ?)
            OR custom_metadata LIKE ?
            OR source_app LIKE ?
            OR content LIKE ?
         ORDER BY created_at DESC LIMIT 500
         """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(dbManager.getDB(), sql, -1, &statement, nil) == SQLITE_OK {
             sqlite3_bind_text(statement, 1, (ftsQuery as NSString).utf8String, -1, nil)
             sqlite3_bind_text(statement, 2, (likeQuery as NSString).utf8String, -1, nil)
             sqlite3_bind_text(statement, 3, (likeQuery as NSString).utf8String, -1, nil)
             sqlite3_bind_text(statement, 4, (likeQuery as NSString).utf8String, -1, nil)
             
            while sqlite3_step(statement) == SQLITE_ROW {
                if let item = parseItem(from: statement) {
                    items.append(item)
                }
            }
        } else {
             print("Search prepare failed")
        }
        sqlite3_finalize(statement)
        return items
    }
    
    func findDuplicates(of item: ClipboardItem) -> [ClipboardItem] {
        var items: [ClipboardItem] = []
        let sql: String
        let bindValue: String
        
        switch item.data {
        case .text(let text, _):
            sql = "SELECT * FROM clipboard_items WHERE type = 'text' AND (content = ? OR trim(content) = ?)"
            bindValue = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .color(let hex):
            sql = "SELECT * FROM clipboard_items WHERE type = 'color' AND lower(content) = ?"
            bindValue = hex.lowercased()
        case .image(let path):
            sql = "SELECT * FROM clipboard_items WHERE type = 'image' AND content = ?"
            bindValue = path
        }
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(dbManager.getDB(), sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (bindValue as NSString).utf8String, -1, nil)
            if case .text = item.data {
                sqlite3_bind_text(statement, 2, (bindValue as NSString).utf8String, -1, nil)
            }
            while sqlite3_step(statement) == SQLITE_ROW {
                if let found = parseItem(from: statement), found.id != item.id {
                    items.append(found)
                }
            }
        }
        sqlite3_finalize(statement)
        return items
    }
    
    func insert(_ item: ClipboardItem) {
        let sql = """
        INSERT OR REPLACE INTO clipboard_items 
        (id, type, content, source_url, created_at, source_app, is_pinned, copy_count, custom_metadata) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(dbManager.getDB(), sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (item.id.uuidString as NSString).utf8String, -1, nil)
            
            // Extract Type and Content
            var typeStr = ""
            var contentStr = ""
            var sourceUrlStr: String? = nil
            
            switch item.data {
            case .text(let text, let url):
                typeStr = "text"
                contentStr = text
                sourceUrlStr = url
            case .color(let hex):
                typeStr = "color"
                contentStr = hex
            case .image(let filename):
                typeStr = "image"
                contentStr = filename
            }
            
            sqlite3_bind_text(statement, 2, (typeStr as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (contentStr as NSString).utf8String, -1, nil)
            
            if let url = sourceUrlStr {
                 sqlite3_bind_text(statement, 4, (url as NSString).utf8String, -1, nil)
            } else {
                 sqlite3_bind_null(statement, 4)
            }
            
            sqlite3_bind_double(statement, 5, item.createdAt.timeIntervalSinceReferenceDate)
            
            if let app = item.sourceApp {
                sqlite3_bind_text(statement, 6, (app as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            
            sqlite3_bind_int(statement, 7, item.isPinned ? 1 : 0)
            sqlite3_bind_int(statement, 8, Int32(item.copyCount))
            
            if let meta = item.customMetadata {
                sqlite3_bind_text(statement, 9, (meta as NSString).utf8String, -1, nil)
            } else {
                 sqlite3_bind_null(statement, 9)
            }
            
            if sqlite3_step(statement) != SQLITE_DONE {
                print("Error inserting item")
            }
        }
        sqlite3_finalize(statement)
    }
    
    // Add compatibility Delete used by ViewModel
    func delete(id: UUID) {
         let sql = "DELETE FROM clipboard_items WHERE id = ?"
         var statement: OpaquePointer?
         if sqlite3_prepare_v2(dbManager.getDB(), sql, -1, &statement, nil) == SQLITE_OK {
             sqlite3_bind_text(statement, 1, (id.uuidString as NSString).utf8String, -1, nil)
             sqlite3_step(statement)
         }
         sqlite3_finalize(statement)
    }
    
    func deleteAll() {
        dbManager.execute(sql: "DELETE FROM clipboard_items")
    }

    private func parseItem(from statement: OpaquePointer?) -> ClipboardItem? {
        guard let idStr = sqlite3_column_text(statement, 0) else { return nil }
        guard let id = UUID(uuidString: String(cString: idStr)) else { return nil }
        
        guard let typeStr = sqlite3_column_text(statement, 1) else { return nil }
        let type = String(cString: typeStr)
        
        guard let contentStr = sqlite3_column_text(statement, 2) else { return nil }
        let content = String(cString: contentStr)
        
        var sourceUrl: String? = nil
        if let urlStr = sqlite3_column_text(statement, 3) {
            sourceUrl = String(cString: urlStr)
        }
        
        let createdAtDouble = sqlite3_column_double(statement, 4)
        let createdAt = Date(timeIntervalSinceReferenceDate: createdAtDouble)
        
        var sourceApp: String? = nil
        if let appStr = sqlite3_column_text(statement, 5) {
            sourceApp = String(cString: appStr)
        }
        
        let isPinned = sqlite3_column_int(statement, 6) != 0
        let copyCount = Int(sqlite3_column_int(statement, 7))
        
        var meta: String? = nil
        if let metaStr = sqlite3_column_text(statement, 8) {
            meta = String(cString: metaStr)
        }
        
        var data: ClipboardData
        switch type {
        case "text":
            data = .text(content, sourceURL: sourceUrl)
        case "color":
            data = .color(content)
        case "image":
            data = .image(content)
        default:
            return nil
        }
        
        return ClipboardItem(
            id: id,
            data: data,
            createdAt: createdAt,
            sourceApp: sourceApp,
            isPinned: isPinned,
            copyCount: copyCount,
            customMetadata: meta
        )
    }
    
    func deleteImage(_ filename: String) {
        let fileManager = FileManager.default
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let fileURL = appSupportURL.appendingPathComponent("Clipy").appendingPathComponent(filename)
            try? fileManager.removeItem(at: fileURL)
        }
    }
    
    func deduplicate() {
        print("[HistoryRepository] Starting deduplication...")
        
        // 1. Load ALL items for complete deduplication across the database
        let allItems = load(limit: 100000)
        
        // 2. Group by Content normalizationKey (ignoring source app)
        var uniqueGroups: [String: [ClipboardItem]] = [:]
        
        for item in allItems {
            var key = item.data.normalizationKey
            
            if case .image(let path) = item.data {
                if let hash = computeFileHash(path: path) {
                    key = "image_hash:" + hash
                } else {
                    key = "image_path:" + path
                }
            } else if case .color = item.data {
                key = "color:" + key
            } else {
                key = "text:" + key
            }
            
            uniqueGroups[key, default: []].append(item)
        }
        
        var deletedCount = 0
        
        for (_, group) in uniqueGroups where group.count > 1 {
            // Sort by createdAt descending so keeper is the newest copy
            let sorted = group.sorted { $0.createdAt > $1.createdAt }
            
            guard var keeper = sorted.first else { continue }
            let duplicates = sorted.dropFirst()
            
            // Merge metadata from any older duplicate entries into keeper
            if keeper.customMetadata == nil {
                keeper.customMetadata = group.compactMap { $0.customMetadata }.first
            }
            if !keeper.isPinned && group.contains(where: { $0.isPinned }) {
                keeper.isPinned = true
            }
            if keeper.sourceApp == nil {
                keeper = ClipboardItem(
                    id: keeper.id,
                    data: keeper.data,
                    createdAt: keeper.createdAt,
                    sourceApp: group.compactMap { $0.sourceApp }.first,
                    isPinned: keeper.isPinned,
                    copyCount: keeper.copyCount,
                    customMetadata: keeper.customMetadata
                )
            }
            if case .text(let text, let url) = keeper.data, url == nil {
                let firstURL = group.compactMap { item -> String? in
                    if case .text(_, let u) = item.data { return u }
                    return nil
                }.first
                if let oldURL = firstURL {
                    keeper = ClipboardItem(
                        id: keeper.id,
                        data: .text(text, sourceURL: oldURL),
                        createdAt: keeper.createdAt,
                        sourceApp: keeper.sourceApp,
                        isPinned: keeper.isPinned,
                        copyCount: keeper.copyCount,
                        customMetadata: keeper.customMetadata
                    )
                }
            }
            
            let totalCopies = group.reduce(0) { $0 + $1.copyCount }
            keeper.copyCount = totalCopies
            
            // Persist merged keeper to database
            insert(keeper)
            
            for dup in duplicates {
                delete(id: dup.id)
                deletedCount += 1
                
                if case .image(let dupPath) = dup.data,
                   case .image(let keeperPath) = keeper.data,
                   dupPath != keeperPath {
                    deleteImage(dupPath)
                }
            }
        }
        
        print("[HistoryRepository] Deduplication complete. Merged and removed \(deletedCount) duplicate items.")
        UserDefaults.standard.set(true, forKey: "has_deduplicated_history_v1")
    }
    
    private func computeFileHash(path: String) -> String? {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let fileURL = appSupportURL.appendingPathComponent("Clipy").appendingPathComponent(path)
        
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        
        let hashData = SHA256.hash(data: data)
        return hashData.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func updateCopyCount(id: UUID, count: Int) {
        let sql = "UPDATE clipboard_items SET copy_count = ? WHERE id = ?"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(dbManager.getDB(), sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(count))
            sqlite3_bind_text(statement, 2, (id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
}
