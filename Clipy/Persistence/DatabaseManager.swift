//
//  DatabaseManager.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import Foundation
import SQLite3

class DatabaseManager {
    static let shared = DatabaseManager()
    
    private var db: OpaquePointer?
    private let dbPath: String
    
    init() {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access Application Support directory")
        }
        
        let appDirectoryURL = appSupportURL.appendingPathComponent("Clipy")
        if !fileManager.fileExists(atPath: appDirectoryURL.path) {
            try? fileManager.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        self.dbPath = appDirectoryURL.appendingPathComponent("clipy.sqlite").path
        openDatabase()
        createTables()
    }
    
    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Error opening database")
        }
    }
    
    private func createTables() {
        let createTableString = """
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            content TEXT NOT NULL,
            source_url TEXT,
            created_at REAL NOT NULL,
            source_app TEXT,
            is_pinned INTEGER DEFAULT 0,
            copy_count INTEGER DEFAULT 1,
            custom_metadata TEXT
        );
        """
        
        execute(sql: createTableString)
        
        // Check if existing FTS5 table has custom_metadata column
        var needsRebuild = false
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT sql FROM sqlite_master WHERE type='table' AND name='clipboard_search'", -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                if let sqlC = sqlite3_column_text(statement, 0) {
                    let sqlStr = String(cString: sqlC)
                    if !sqlStr.contains("custom_metadata") {
                        needsRebuild = true
                    }
                }
            } else {
                // Table doesn't exist yet
                needsRebuild = true
            }
        }
        sqlite3_finalize(statement)
        
        if needsRebuild {
            execute(sql: "DROP TRIGGER IF EXISTS clipboard_ai;")
            execute(sql: "DROP TRIGGER IF EXISTS clipboard_ad;")
            execute(sql: "DROP TRIGGER IF EXISTS clipboard_au;")
            execute(sql: "DROP TABLE IF EXISTS clipboard_search;")
        }
        
        // FTS5 Virtual Table for Search
        let createFTSString = """
        CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_search USING fts5(
            content,
            source_app,
            custom_metadata,
            content='clipboard_items',
            content_rowid='rowid'
        );
        """
        execute(sql: createFTSString)
        
        // Triggers to keep FTS in sync
        let triggers = [
            """
            CREATE TRIGGER IF NOT EXISTS clipboard_ai AFTER INSERT ON clipboard_items BEGIN
              INSERT INTO clipboard_search(rowid, content, source_app, custom_metadata) VALUES (new.rowid, new.content, new.source_app, new.custom_metadata);
            END;
            """,
            """
            CREATE TRIGGER IF NOT EXISTS clipboard_ad AFTER DELETE ON clipboard_items BEGIN
              INSERT INTO clipboard_search(clipboard_search, rowid, content, source_app, custom_metadata) VALUES('delete', old.rowid, old.content, old.source_app, old.custom_metadata);
            END;
            """,
            """
            CREATE TRIGGER IF NOT EXISTS clipboard_au AFTER UPDATE ON clipboard_items BEGIN
              INSERT INTO clipboard_search(clipboard_search, rowid, content, source_app, custom_metadata) VALUES('delete', old.rowid, old.content, old.source_app, old.custom_metadata);
              INSERT INTO clipboard_search(rowid, content, source_app, custom_metadata) VALUES (new.rowid, new.content, new.source_app, new.custom_metadata);
            END;
            """
        ]
        
        for trigger in triggers {
            execute(sql: trigger)
        }
        
        if needsRebuild {
            execute(sql: "INSERT INTO clipboard_search(clipboard_search) VALUES('rebuild');")
        }
    }
    
    func execute(sql: String) {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) != SQLITE_DONE {
                print("Error executing SQL: \(sql)")
                if let errorMsg = sqlite3_errmsg(db) {
                     print("Message: \(String(cString: errorMsg))")
                }
            }
        } else {
            print("Error preparing SQL: \(sql)")
            if let errorMsg = sqlite3_errmsg(db) {
                 print("Message: \(String(cString: errorMsg))")
            }
        }
        sqlite3_finalize(statement)
    }
    
    func getDB() -> OpaquePointer? {
        return db
    }
}
