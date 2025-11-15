//
//  Styles.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI

struct SearchBarStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.luminaTextSecondary)
                .font(.system(size: 14))
            configuration
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.obsidianSurface)
        .cornerRadius(8)
        .foregroundColor(.luminaTextPrimary)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.obsidianBorder, lineWidth: 0.5)
        )
    }
}

struct AppButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(configuration.isPressed ? Color.obsidianSurface.opacity(0.8) : Color.obsidianSurface)
            .cornerRadius(6)
            .foregroundColor(.luminaTextPrimary)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.obsidianBorder, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

