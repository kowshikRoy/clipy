//
//  ClipboardListView.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI

struct ClipboardListView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let onPaste: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Area
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.luminaTextSecondary)
                    TextField("Search...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.custom("Roboto", size: 14))
                        .fontWeight(.medium)
                        .foregroundColor(.luminaTextPrimary)
                        .onSubmit {
                            onPaste()
                        }
                }
                .padding(8)
                .background(Color.obsidianSurface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.obsidianBorder, lineWidth: 0.5)
                )
            }
            .padding(16)
            .background(Color.obsidianSurface.opacity(0.5))
            .zIndex(2)
            
            // Pinned Section (Fixed)
            if !viewModel.pinnedItems.isEmpty {
                VStack(spacing: 0) {
                    sectionHeader(title: "Pinned", icon: "pin.fill")
                    
                    VStack(spacing: 0) {
                        ForEach(viewModel.pinnedItems) { item in
                            LuminaRow(item: item, isSelected: viewModel.selectedItemID == item.id)
                                .id(item.id)
                                .onTapGesture {
                                    viewModel.selectedItemID = item.id
                                }
                        }
                    }
                }
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.obsidianBorder),
                    alignment: .bottom
                )
                .zIndex(1)
            }
            
            // Recent Section (Scrollable)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.categorizedHistory, id: \.0) { category, items in
                            Section(header: sectionHeader(title: category.title.uppercased(), icon: category.icon)) {
                                ForEach(items) { item in
                                    LuminaRow(item: item, isSelected: viewModel.selectedItemID == item.id)
                                        .id(item.id)
                                        .onTapGesture {
                                            viewModel.selectedItemID = item.id
                                        }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
                .background(
                    // Hidden keyboard shortcuts for navigation
                    ZStack {
                        Button("") { viewModel.moveSelection(offset: -1, proxy: proxy) }
                            .keyboardShortcut(.upArrow, modifiers: [])
                        Button("") { viewModel.moveSelection(offset: 1, proxy: proxy) }
                            .keyboardShortcut(.downArrow, modifiers: [])
                    }
                    .frame(width: 0, height: 0)
                    .opacity(0)
                )
            }
        }
    }
    
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.luminaTextSecondary)
            Text(title)
                .font(.custom("Roboto", size: 11))
                .fontWeight(.bold)
                .foregroundColor(.luminaTextSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Color.obsidianBackground
                .opacity(0.95)
        )
    }
}
