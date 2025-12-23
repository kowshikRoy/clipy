//
//  DetailStageView.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI

struct DetailStageView: View {
    let item: ClipboardItem
    @Binding var isEditing: Bool
    @Binding var editingText: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Adaptive Header
            HStack {
                let (icon, color, title): (String, Color, String) = {
                    switch item.data {
                    case .text:
                        return ("doc.text", .luminaTextPrimary, "Text")
                    case .color:
                        return ("paintpalette", .purple.opacity(0.8), "Color")
                    case .image:
                        return ("photo", .pink.opacity(0.8), "Image")
                    }
                }()
                
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.custom("Roboto", size: 24))
                    .fontWeight(.light)
                    .foregroundColor(.luminaTextPrimary)
                
                Spacer()
                
                if isEditing {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.plain)
                        .foregroundColor(.luminaTextSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                    
                    Button("Save", action: onSave)
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                }
            }
            .padding(.bottom, 20)
            
            // Content
            if isEditing {
                TextEditor(text: $editingText)
                    .font(.custom("Roboto", size: 14))
                    .foregroundColor(.luminaTextPrimary)
                    .padding(4)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )
            } else {
                // Display image or text
                if case .image(let filename) = item.data {
                    if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                        let fileURL = appSupportURL.appendingPathComponent("Clipy").appendingPathComponent(filename)
                        if let nsImage = NSImage(contentsOf: fileURL) {
                            GeometryReader { geometry in
                                ScrollView([.horizontal, .vertical]) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                                        .cornerRadius(8)
                                }
                            }
                        } else {
                            Text("Image not found")
                                .foregroundColor(.luminaTextSecondary)
                        }
                    } else {
                        Text("Error loading image")
                            .foregroundColor(.luminaTextSecondary)
                    }

                } else {
                    ScrollView {
                        Text(item.textRepresentation)
                            .font(.custom("Roboto", size: 14))
                            .foregroundColor(.luminaTextPrimary)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            
            Spacer()
            
            // Metadata Panel
            VStack(alignment: .leading, spacing: 5) {
                Text("Metadata")
                   .font(.custom("Roboto", size: 12))
                   .fontWeight(.bold)
                   .foregroundColor(.luminaTextSecondary)
                   .padding(.horizontal, 16)
                   .padding(.bottom, 5)

                VStack(spacing: 0) {
                    if let source = item.sourceApp {
                        MetadataRow(icon: "app.dashed", label: "Source", value: source, appIcon: iconForApp(source))
                    }

                    if let metadata = item.customMetadata {
                        MetadataRow(icon: "tag", label: "Note", value: metadata)
                    }
                    
                    if item.copyCount > 1 {
                        MetadataRow(icon: "doc.on.doc", label: "Copied", value: "\(item.copyCount) times")
                    } else {
                        MetadataRow(icon: "doc.on.doc", label: "Copied", value: "1 time")
                    }
                    
                    if case .text(let text, let sourceURL) = item.data {
                        // Show source URL if available
                        if let url = sourceURL, let host = URL(string: url)?.host {
                            MetadataRow(icon: "link", label: "URL", value: host)
                        }
                        
                        let byteCount = text.utf8.count
                        let sizeString = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
                        MetadataRow(icon: "arrow.up.left.and.arrow.down.right", label: "Size", value: sizeString)
                    }
                    
                    if case .image(let filename) = item.data {
                        // Show image dimensions
                        if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                            let fileURL = appSupportURL.appendingPathComponent("Clipy").appendingPathComponent(filename)
                            if let nsImage = NSImage(contentsOf: fileURL) {
                                let width = Int(nsImage.size.width)
                                let height = Int(nsImage.size.height)
                                MetadataRow(icon: "arrow.up.left.and.arrow.down.right", label: "Size", value: "\(width) × \(height)")
                            }
                        }
                    }
                    
                    MetadataRow(icon: "calendar", label: "Date", value: item.createdAt.formatted(date: .numeric, time: .shortened))
                    
                    let typeTitle: String = {
                        switch item.data {
                        case .text: return "Text"
                        case .color: return "Color"
                        case .image: return "Image"
                        }
                    }()
                    MetadataRow(icon: "folder", label: "Type", value: typeTitle)
                }
                .padding(.vertical, 8)

                .background(Color.obsidianSurface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.obsidianBorder, lineWidth: 0.5)
                )
            }
        }
        .padding(24)
        .background(Color.clear)
    }
    
    private func iconForApp(_ name: String) -> NSImage? {
        let path = "/Applications/\(name).app"
        if FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        
        let systemPath = "/System/Applications/\(name).app"
        if FileManager.default.fileExists(atPath: systemPath) {
            return NSWorkspace.shared.icon(forFile: systemPath)
        }
        
        return nil
    }
}
