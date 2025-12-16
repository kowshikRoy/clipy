//
//  LuminaRow.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI

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
        .contentShape(Rectangle()) // Ensure entire row is clickable
    }
    
    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.createdAt, relativeTo: Date())
    }
}
