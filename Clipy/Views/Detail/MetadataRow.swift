//
//  MetadataRow.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI

struct MetadataRow: View {
    let icon: String
    let label: String
    var value: String = ""
    var appIcon: NSImage? = nil
    var localizeValue: Bool = false
    var localizedKey: LocalizedStringKey? = nil
    
    var body: some View {
        HStack(spacing: 0) { // Zero spacing, controlled by frame/padding
            if let appIcon = appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3.5))
                    .padding(.trailing, 8)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.luminaTextSecondary)
                    .frame(width: 16)
                    .padding(.trailing, 8)
            }
                
            Text(LocalizedStringKey(label))
                .font(.custom("Roboto", size: 13))
                .foregroundColor(.luminaTextSecondary)
                .frame(width: 68, alignment: .leading) // Fixed width for alignment
                .lineLimit(1)
                
            Group {
                if let localizedKey = localizedKey {
                    Text(localizedKey)
                } else if localizeValue {
                    Text(LocalizedStringKey(value))
                } else {
                    Text(value)
                }
            }
            .font(.custom("Roboto", size: 13))
            .fontWeight(.medium)
            .foregroundColor(.luminaTextPrimary)
            .lineLimit(1)
            .truncationMode(.tail)
                
            Spacer() 
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4) // Tighter vertical padding for "list" feel
    }
}
