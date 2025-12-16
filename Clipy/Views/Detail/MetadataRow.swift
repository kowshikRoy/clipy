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
    let value: String
    var appIcon: NSImage? = nil
    
    var body: some View {
        HStack(spacing: 0) { // Zero spacing, controlled by frame/padding
            if let appIcon = appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .padding(.trailing, 8)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.luminaTextSecondary)
                    .frame(width: 16)
                    .padding(.trailing, 8)
            }
                
            Text(label)
                .font(.custom("Roboto", size: 13))
                .foregroundColor(.luminaTextSecondary)
                .frame(width: 50, alignment: .leading) // Fixed width for alignment
                
            Text(value)
                .font(.custom("Roboto", size: 13))
                .fontWeight(.medium)
                .foregroundColor(.luminaTextPrimary)
                
            Spacer() 
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4) // Tighter vertical padding for "list" feel
    }
}
