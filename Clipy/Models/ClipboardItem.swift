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
