//
//  ClipboardItem.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI
import Foundation

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
    
    // MARK: - Lifecycle & Codable
    
    enum CodingKeys: String, CodingKey {
        case id, data, createdAt, sourceApp, isPinned, copyCount, customMetadata
    }
    
    init(id: UUID = UUID(), 
         data: ClipboardData, 
         createdAt: Date = Date(), 
         sourceApp: String?, 
         isPinned: Bool = false, 
         copyCount: Int = 1, 
         customMetadata: String? = nil) {
        self.id = id
        self.data = data
        self.createdAt = createdAt
        self.sourceApp = sourceApp
        self.isPinned = isPinned
        self.copyCount = copyCount
        self.customMetadata = customMetadata
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.data = try container.decode(ClipboardData.self, forKey: .data)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp)
        self.isPinned = try container.decode(Bool.self, forKey: .isPinned)
        self.copyCount = try container.decode(Int.self, forKey: .copyCount)
        self.customMetadata = try container.decodeIfPresent(String.self, forKey: .customMetadata)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(data, forKey: .data)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(sourceApp, forKey: .sourceApp)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(copyCount, forKey: .copyCount)
        try container.encode(customMetadata, forKey: .customMetadata)
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
            
            return false
        }
    }
}
