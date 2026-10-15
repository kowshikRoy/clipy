//
//  ClipboardListView.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI

struct ClipboardListView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    @ObservedObject var permissionMonitor: PermissionMonitor
    let onPaste: () -> Void
    
    @State private var keyMonitor: Any?
    @State private var lastKeyRepeatTime: TimeInterval = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Search & Filter Area
            VStack(spacing: 12) {
                // Search Field
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.luminaTextSecondary)
                        TextField("Search history, #tag, app...", text: $viewModel.searchText)
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
                
                // Filter Picker
                Picker("Filter", selection: $viewModel.filterType) {
                    ForEach(ClipboardViewModel.FilterType.allCases) { type in
                        Text(LocalizedStringKey(type.rawValue)).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(16)
            .background(Color.obsidianSurface.opacity(0.5))
            .zIndex(2)
            
            if !permissionMonitor.isTrusted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 11))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Auto-Paste")
                            .font(.custom("Roboto", size: 11))
                            .fontWeight(.semibold)
                            .foregroundColor(.luminaTextPrimary)
                        Text("Allow Clipy in Accessibility Settings to paste directly.")
                            .font(.custom("Roboto", size: 10))
                            .foregroundColor(.luminaTextSecondary)
                    }
                    Spacer()
                    Button("Open Settings") {
                        permissionMonitor.openAccessibilitySettings()
                    }
                    .buttonStyle(AppButtonStyle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.yellow.opacity(0.12))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.yellow.opacity(0.3)),
                    alignment: .bottom
                )
                .zIndex(2)
            }
            
            // Pinned Section (Fixed)
            if !viewModel.pinnedItems.isEmpty {
                VStack(spacing: 0) {
                    sectionHeader(title: "Pinned", icon: "pin.fill")
                    
                    VStack(spacing: 0) {
                        ForEach(viewModel.pinnedItems) { item in
                            LuminaRow(
                                item: item,
                                isSelected: viewModel.selectedItemID == item.id,
                                onSelect: { viewModel.selectedItemID = item.id }
                            )
                            .equatable()
                            .id(item.id)
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
                    // Hidden anchor to scroll to the absolute top
                    Color.clear.frame(height: 1).id("top-anchor")
                    
                    LazyVStack(spacing: 0) {
                        if viewModel.searchText.isEmpty {
                            ForEach(viewModel.categorizedHistory) { section in
                                Section(header: sectionHeader(title: section.category.title, icon: section.category.icon).id(section.category.title)) {
                                    ForEach(section.items) { item in
                                        LuminaRow(
                                            item: item,
                                            isSelected: viewModel.selectedItemID == item.id,
                                            onSelect: { viewModel.selectedItemID = item.id }
                                        )
                                        .equatable()
                                        .id(item.id)
                                    }
                                }
                            }
                        } else {
                            // Flat list during search
                            ForEach(viewModel.unpinnedHistory) { item in
                                LuminaRow(
                                    item: item,
                                    isSelected: viewModel.selectedItemID == item.id,
                                    onSelect: { viewModel.selectedItemID = item.id }
                                )
                                .equatable()
                                .id(item.id)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    installKeyMonitor(proxy: proxy)
                }
                .onDisappear {
                    removeKeyMonitor()
                }
                .onReceive(viewModel.newItemAdded) { _ in
                    // Scroll to top-anchor when a new item is added
                    DispatchQueue.main.async {
                        withAnimation {
                            proxy.scrollTo("top-anchor", anchor: .top)
                        }
                    }
                }
            }
        }
    }
    
    private func installKeyMonitor(proxy: ScrollViewProxy) {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 126 || event.keyCode == 125 else {
                return event
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard modifiers.isEmpty,
                  !viewModel.isEditing,
                  let window = event.window,
                  window == ClipyApp.mainAppWindow else {
                return event
            }
            
            if event.isARepeat {
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastKeyRepeatTime < 0.025 {
                    return nil
                }
                lastKeyRepeatTime = now
            }
            
            if event.keyCode == 126 {
                viewModel.moveSelection(offset: -1, proxy: proxy)
            } else {
                viewModel.moveSelection(offset: 1, proxy: proxy)
            }
            return nil
        }
    }
    
    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
    
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.luminaTextSecondary)
            Text(LocalizedStringKey(title))
                .textCase(.uppercase)
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
