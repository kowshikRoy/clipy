//
//  Color+Extensions.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI

extension Color {
    // Project Lumina Palette
    static let obsidianBackground = Color(nsColor: NSColor(hex: "#050505").withAlphaComponent(0.85)) // Deep translucent black
    static let obsidianSurface = Color(nsColor: NSColor(hex: "#1A1A1A").withAlphaComponent(0.5)) // Lighter surface
    static let obsidianBorder = Color(nsColor: NSColor(hex: "#FFFFFF").withAlphaComponent(0.08)) // Subtle rim light
    static let luminaTextPrimary = Color(nsColor: NSColor(hex: "#EDEDED"))
    static let luminaTextSecondary = Color(nsColor: NSColor(hex: "#A0A0A0"))
    static let luminaAccent = Color(nsColor: NSColor(hex: "#D4D4D4")) // Default silver glow

}

extension NSColor {
    convenience init(hex: String) {
        let trimHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let dropHash = String(trimHex.dropFirst())
        let hexString = trimHex.hasPrefix("#") ? dropHash : trimHex
        let ui64 = UInt64(hexString, radix: 16)
        let r, g, b, a: UInt64
        switch hexString.count {
        case 3:
            (a, r, g, b) = (255, (ui64! & 0xF00) * 17, (ui64! & 0x0F0) * 17, (ui64! & 0x00F) * 17)
        case 6:
            (a, r, g, b) = (255, (ui64! & 0xFF0000) >> 16, (ui64! & 0x00FF00) >> 8, ui64! & 0x0000FF)
        case 8:
            (a, r, g, b) = ((ui64! & 0xFF000000) >> 24, (ui64! & 0x00FF0000) >> 16, (ui64! & 0x0000FF00) >> 8, ui64! & 0x000000FF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}
