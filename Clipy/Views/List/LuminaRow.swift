//
//  LuminaRow.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI

struct LuminaRow: View, Equatable {
    let item: ClipboardItem
    let isSelected: Bool
    @State private var isHovering = false
    
    static func == (lhs: LuminaRow, rhs: LuminaRow) -> Bool {
        return lhs.item.id == rhs.item.id &&
               lhs.isSelected == rhs.isSelected &&
               lhs.item.customMetadata == rhs.item.customMetadata
    }
    
    private var previewText: String {
        let lines = item.textRepresentation.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return item.textRepresentation.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Show thumbnail for images
            if case .image(let filename) = item.data {
                AsyncThumbnailView(filename: filename)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: iconName(for: item.data))
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .luminaTextPrimary : .luminaTextSecondary)
                    .frame(width: 20, height: 20)
            }
            
            Text(previewText)
                .font(.custom("Roboto", size: 13))
                .fontWeight(.regular)
                .foregroundColor(isSelected ? .luminaTextPrimary : .luminaTextSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                
            Spacer() // Force left alignment
            
            if let metadata = item.customMetadata, !metadata.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 9))
                    Text(metadata)
                        .font(.custom("Roboto", size: 10))
                        .lineLimit(1)
                }
                .foregroundColor(isSelected ? .luminaTextPrimary : .luminaTextSecondary.opacity(0.85))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(isSelected ? 0.2 : 0.1))
                .cornerRadius(4)
            }
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
    private func iconName(for data: ClipboardData) -> String {
        switch data {
        case .text: return "doc.text"
        case .color: return "paintpalette"
        case .image: return "photo"
        }
    }
}

struct AsyncThumbnailView: View {
    let filename: String
    @State private var image: NSImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.obsidianSurface
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.5)
                    } else {
                        Image(systemName: "photo")
                            .foregroundColor(.luminaTextSecondary)
                    }
                }
            }
        }
        .task(priority: .userInitiated) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        let loadedImage = await ImageLoader.shared.loadImage(filename: filename)
        await MainActor.run {
            self.image = loadedImage
            self.isLoading = false
        }
    }
}
