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
    
    /// Returns a version of the content suitable for deduplication (ignoring whitespace and metadata)
    var normalizationKey: String {
        switch self {
        case .text(let string, _):
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case .color(let hex):
            return hex.lowercased()
        case .image(let path):
            return path // Images are already deduplicated by SHA256 hash in PasteboardService
        }
    }
}

struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let data: ClipboardData
    let createdAt: Date
    var sourceApp: String?
    var isPinned: Bool = false
    var copyCount: Int = 1
    var customMetadata: String? = nil
    var urlTitle: String? = nil
    var urlDescription: String? = nil
    var ocrText: String? = nil
    
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
    
    /// If the copied text itself is a standalone HTTP/HTTPS URL, returns it.
    var directURL: URL? {
        guard case .text(let string, _) = data else { return nil }
        return Self.parseValidWebURL(string)
    }
    
    /// Returns either the direct URL (if the clip is a URL) or the source webpage URL (if copied from a browser).
    var detectedURL: URL? {
        if let direct = directURL {
            return direct
        }
        if case .text(_, let sourceURL) = data, let src = sourceURL {
            return Self.parseValidWebURL(src)
        }
        return nil
    }
    
    var isDirectURL: Bool {
        directURL != nil
    }
    
    var hasLink: Bool {
        detectedURL != nil
    }
    
    static func parseValidWebURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        // Valid if host is a domain/IP (contains '.') OR has a non-empty path on an intranet host (e.g. http://go/foo)
        let hasValidHost = host.contains(".") || (components.path.count > 1 && components.path.hasPrefix("/"))
        guard hasValidHost else { return nil }
        return components.url
    }
    
    // MARK: - Lifecycle & Codable
    
    enum CodingKeys: String, CodingKey {
        case id, data, createdAt, sourceApp, isPinned, copyCount, customMetadata, urlTitle, urlDescription, ocrText
    }
    
    init(id: UUID = UUID(), 
         data: ClipboardData, 
         createdAt: Date = Date(), 
         sourceApp: String?, 
         isPinned: Bool = false, 
         copyCount: Int = 1, 
         customMetadata: String? = nil,
         urlTitle: String? = nil,
         urlDescription: String? = nil,
         ocrText: String? = nil) {
        self.id = id
        self.data = data
        self.createdAt = createdAt
        self.sourceApp = sourceApp
        self.isPinned = isPinned
        self.copyCount = copyCount
        self.customMetadata = customMetadata
        self.urlTitle = urlTitle
        self.urlDescription = urlDescription
        self.ocrText = ocrText
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
        self.urlTitle = try container.decodeIfPresent(String.self, forKey: .urlTitle)
        self.urlDescription = try container.decodeIfPresent(String.self, forKey: .urlDescription)
        self.ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
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
        try container.encodeIfPresent(urlTitle, forKey: .urlTitle)
        try container.encodeIfPresent(urlDescription, forKey: .urlDescription)
        try container.encodeIfPresent(ocrText, forKey: .ocrText)
    }
    
    func matches(_ query: String) -> Bool {
        let terms = query.lowercased().split(separator: " ")
        guard !terms.isEmpty else { return true }
        
        return terms.allSatisfy { term in
            var termString = String(term)
            if termString.hasPrefix("#") {
                termString = String(termString.dropFirst())
            } else if termString.hasPrefix("tag:") {
                termString = String(termString.dropFirst(4))
            } else if termString.hasPrefix("note:") {
                termString = String(termString.dropFirst(5))
            }
            
            // 0. Custom Metadata (Tag/Note) Match
            if let meta = customMetadata?.lowercased(), meta.contains(termString) {
                return true
            }
            
            // 1. Content Match
            if textRepresentation.lowercased().contains(termString) { return true }
            
            // 2. Metadata Match (Source App)
            if let app = sourceApp?.lowercased(), app.contains(termString) { return true }
            
            // 3. URL Metadata Match
            if let title = urlTitle?.lowercased(), title.contains(termString) { return true }
            if let desc = urlDescription?.lowercased(), desc.contains(termString) { return true }
            
            // 4. OCR Text Match
            if let ocr = ocrText?.lowercased(), ocr.contains(termString) { return true }
            
            return false
        }
    }
}
