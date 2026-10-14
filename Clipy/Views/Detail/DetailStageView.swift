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
    var isEnriching: Bool = false
    let onSave: () -> Void
    let onCancel: () -> Void
    var onOpenURL: (() -> Void)? = nil
    var onCopyOCRText: ((String) -> Void)? = nil
    
    @State private var websiteLogo: NSImage? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Adaptive Header/Actions
            if isEditing {
                HStack {
                    Spacer()
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
                .padding(.bottom, 10)
            }
            
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
                    VStack(alignment: .leading, spacing: 12) {
                        if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                            let fileURL = appSupportURL.appendingPathComponent("Clipy").appendingPathComponent(filename)
                            if let nsImage = NSImage(contentsOf: fileURL) {
                                GeometryReader { geometry in
                                    ScrollView([.horizontal, .vertical]) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                                            .cornerRadius(4)
                                    }
                                    .frame(maxHeight: .infinity)
                                    .padding(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.obsidianBorder, lineWidth: 1)
                                    )
                                }
                            } else {
                                Text("Image not found")
                                    .foregroundColor(.luminaTextSecondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        } else {
                            Text("Error loading image")
                                .foregroundColor(.luminaTextSecondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        
                        // OCR Extracted Text Card (if text was recognized inside the image)
                        if let ocr = item.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines), !ocr.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "text.viewfinder")
                                        .font(.system(size: 12))
                                        .foregroundColor(.luminaAccent)
                                    Text("Recognized Text (OCR)")
                                        .font(.custom("Roboto", size: 12))
                                        .fontWeight(.semibold)
                                        .foregroundColor(.luminaTextPrimary)
                                    
                                    Spacer()
                                    
                                    Button(action: { onCopyOCRText?(ocr) }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "doc.on.doc")
                                                .font(.system(size: 10))
                                            Text("Copy Text")
                                                .font(.custom("Roboto", size: 11))
                                                .fontWeight(.medium)
                                        }
                                        .foregroundColor(.luminaTextPrimary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(5)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                Text(ocr)
                                    .font(.custom("Roboto", size: 12))
                                    .foregroundColor(.luminaTextSecondary)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }
                            .padding(12)
                            .background(Color.obsidianSurface.opacity(0.75))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.obsidianBorder, lineWidth: 0.5)
                            )
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ScrollView {
                            Text(item.textRepresentation)
                                .font(.custom("Roboto", size: 14))
                                .foregroundColor(.luminaTextPrimary)
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(12)
                        }
                        .frame(maxHeight: .infinity) // Fill space
                        .background(Color.obsidianSurface.opacity(0.3)) 
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.obsidianBorder, lineWidth: 1)
                        )
                        
                        // Website Logo, Title & Quick Description Card (shown for direct URLs and clips with a source webpage URL)
                        if let webURL = item.detectedURL {
                            WebLinkPreviewCard(
                                url: webURL,
                                logo: websiteLogo,
                                title: resolvedWebsiteTitle(for: webURL),
                                description: item.urlDescription,
                                isEnriching: isEnriching,
                                onOpen: { onOpenURL?() }
                            )
                        }
                    }
                }
            }
            
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
                        MetadataRow(icon: "doc.on.doc", label: "Copied", localizedKey: "\(item.copyCount) times")
                    } else {
                        MetadataRow(icon: "doc.on.doc", label: "Copied", localizedKey: "1 time")
                    }
                    
                    if case .text(let text, _) = item.data {
                        // Show Website logo + Website Title (or host) if available
                        if let webURL = item.detectedURL {
                            MetadataRow(
                                icon: "globe",
                                label: "Website",
                                value: metadataWebsiteDisplay(for: webURL),
                                appIcon: websiteLogo
                            )
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
                        if item.isDirectURL { return "Link" }
                        switch item.data {
                        case .text: return "Text"
                        case .color: return "Color"
                        case .image: return "Image"
                        }
                    }()
                    MetadataRow(icon: "folder", label: "Type", value: typeTitle, localizeValue: true)
                }
                .padding(.vertical, 8)
                .fixedSize(horizontal: false, vertical: true)
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
        .task(id: item.detectedURL?.absoluteString) {
            guard let url = item.detectedURL else {
                websiteLogo = nil
                return
            }
            websiteLogo = nil
            let loadedLogo = await URLMetadataService.shared.fetchWebsiteLogo(for: url)
            if !Task.isCancelled {
                websiteLogo = loadedLogo
            }
        }
    }
    
    private func resolvedWebsiteTitle(for url: URL) -> String? {
        if let title = item.urlTitle, !title.isEmpty {
            return title
        }
        return URLMetadataService.synthesizeSmartMetadata(for: url)?.title
    }
    
    private func metadataWebsiteDisplay(for url: URL) -> String {
        let host = url.host ?? url.absoluteString
        if let title = resolvedWebsiteTitle(for: url), !title.isEmpty {
            if title.lowercased() == host.lowercased() || title.lowercased().contains(host.lowercased()) {
                return title
            }
            return "\(title) • \(host)"
        }
        return host
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

struct WebLinkPreviewCard: View {
    let url: URL
    let logo: NSImage?
    let title: String?
    let description: String?
    let isEnriching: Bool
    let onOpen: () -> Void
    
    @State private var isHoveringOpen = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                // Website Logo / Favicon
                Group {
                    if let logo = logo {
                        Image(nsImage: logo)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 26, height: 26)
                            Image(systemName: "globe")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.luminaAccent)
                        }
                    }
                }
                
                // Website Title & Hostname
                VStack(alignment: .leading, spacing: 2) {
                    if let title = title, !title.isEmpty {
                        Text(title)
                            .font(.custom("Roboto", size: 13))
                            .fontWeight(.semibold)
                            .foregroundColor(.luminaTextPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                    }
                    
                    HStack(spacing: 6) {
                        Text(url.host ?? url.absoluteString)
                            .font(.custom("Roboto", size: 11))
                            .fontWeight(.medium)
                            .foregroundColor(.luminaAccent)
                            .lineLimit(1)
                        
                        if isEnriching {
                            ProgressView()
                                .scaleEffect(0.45)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
                
                Spacer()
                
                Button(action: onOpen) {
                    HStack(spacing: 4) {
                        Text("Open")
                            .font(.custom("Roboto", size: 11))
                            .fontWeight(.medium)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.luminaTextPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isHoveringOpen ? Color.white.opacity(0.18) : Color.white.opacity(0.1))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .onHover { isHoveringOpen = $0 }
                .help("Open URL in Browser (⌘O)")
            }
            
            if let description = description, !description.isEmpty {
                Text(description)
                    .font(.custom("Roboto", size: 12))
                    .foregroundColor(.luminaTextSecondary)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(Color.obsidianSurface.opacity(0.85))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.obsidianBorder, lineWidth: 0.75)
        )
    }
}
