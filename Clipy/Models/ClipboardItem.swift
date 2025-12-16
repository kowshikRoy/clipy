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

    // Optimized stored properties
    let smartType: SmartContentType
    let searchableText: String

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
    
    // Custom initializer to compute derived properties
    init(id: UUID, data: ClipboardData, createdAt: Date, sourceApp: String?, isPinned: Bool = false, copyCount: Int = 1, customMetadata: String? = nil) {
        self.id = id
        self.data = data
        self.createdAt = createdAt
        self.sourceApp = sourceApp
        self.isPinned = isPinned
        self.copyCount = copyCount
        self.customMetadata = customMetadata

        // Compute smartType and searchableText once
        let type = ClipboardItem.computeSmartType(for: data)
        self.smartType = type
        self.searchableText = ClipboardItem.computeSearchableText(data: data, sourceApp: sourceApp, smartType: type, customMetadata: customMetadata)
    }

    // Coding Keys
    enum CodingKeys: String, CodingKey {
        case id, data, createdAt, sourceApp, isPinned, copyCount, customMetadata
        case smartType, searchableText
    }

    // Custom decoding for migration
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        data = try container.decode(ClipboardData.self, forKey: .data)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        copyCount = try container.decode(Int.self, forKey: .copyCount)
        customMetadata = try container.decodeIfPresent(String.self, forKey: .customMetadata)

        // Handle migration: if smartType or searchableText are missing, compute them
        if let type = try? container.decodeIfPresent(SmartContentType.self, forKey: .smartType) {
            smartType = type
        } else {
            smartType = ClipboardItem.computeSmartType(for: data)
        }

        if let st = try? container.decodeIfPresent(String.self, forKey: .searchableText) {
            searchableText = st
        } else {
            searchableText = ClipboardItem.computeSearchableText(data: data, sourceApp: sourceApp, smartType: smartType, customMetadata: customMetadata)
        }
    }

    // Helper to compute smart type
    static func computeSmartType(for data: ClipboardData) -> SmartContentType {
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
    
    // Helper to compute searchable text
    static func computeSearchableText(data: ClipboardData, sourceApp: String?, smartType: SmartContentType, customMetadata: String?) -> String {
        var parts: [String] = []

        // 1. Content (Limited to first 50,000 chars to save memory for massive strings)
        switch data {
        case .text(let string, _):
            parts.append(String(string.prefix(50_000)).lowercased())
        case .color(let hex):
            parts.append(hex.lowercased())
        case .image:
            parts.append("image")
        }

        // 2. Source App
        if let app = sourceApp {
            parts.append(app.lowercased())
        }

        // 3. Smart Type Title
        parts.append(smartType.title.lowercased())

        // 4. Custom Metadata
        if let meta = customMetadata {
            parts.append(meta.lowercased())
        }

        return parts.joined(separator: " ")
    }

    func matches(_ query: String) -> Bool {
        // MARK: - Regex Support
        if query.hasPrefix("/") && query.count > 1 {
            let pattern = String(query.dropFirst())
            // Use local text representation for regex to support case-sensitive matching if needed,
            // or just use it because searchableText is lowercased.
            // Note: Creating regex every time might be slow, but this runs in background now.
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: textRepresentation.utf16.count)
                // Limit range to prevent massive stalls on 1MB+ files if the user writes a bad regex
                // But generally acceptable on background thread.
                let searchRange = NSIntersectionRange(range, NSRange(location: 0, length: min(100_000, range.length)))

                if regex.firstMatch(in: textRepresentation, options: [], range: searchRange) != nil {
                    return true
                }
            }
            // Fallback to standard search if regex fails to compile?
            // Or strict: if it looks like regex, it must be regex.
            // Let's go with strict. If it starts with /, we try regex.
            return false
        }

        // MARK: - Standard Token Search
        let terms = query.lowercased().split(separator: " ")
        guard !terms.isEmpty else { return true }
        
        return terms.allSatisfy { term in
            searchableText.contains(term)
        }
    }
}

enum SmartContentType: String, Codable {
    case text
    case url
    case email
    case code
    case color
    case image

    var title: String {
        switch self {
        case .text: return "Text"
        case .url: return "URL"
        case .email: return "Email"
        case .code: return "Code"
        case .color: return "Color"
        case .image: return "Image"
        }
    }
    
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
