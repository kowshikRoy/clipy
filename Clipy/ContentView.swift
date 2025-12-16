//
//  ContentView.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var focusManager: AppFocusManager
    @StateObject private var clipboardViewModel: ClipboardViewModel
    
    // Metadata State for Dialog
    @State private var isAddingMetadata = false
    @State private var metadataInput = ""

    init(settings: AppSettings, focusManager: AppFocusManager) {
        self.appSettings = settings
        self.focusManager = focusManager
        _clipboardViewModel = StateObject(wrappedValue: ClipboardViewModel(settings: settings))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // MARK: - List View (Left)
                ClipboardListView(viewModel: clipboardViewModel, onPaste: pasteToApp)
                    .frame(width: 320)
                    .background(Color.obsidianBackground.opacity(0.6))
                
                Rectangle()
                    .fill(Color.obsidianBorder)
                    .frame(width: 1)
                    .ignoresSafeArea(edges: .vertical)
                
                // MARK: - Detail Stage (Right)
                ZStack {
                    Color.obsidianBackground.opacity(0.6).ignoresSafeArea()
                    
                    if let selectedItem = clipboardViewModel.selectedItem {
                        DetailStageView(
                            item: selectedItem,
                            isEditing: $clipboardViewModel.isEditing,
                            editingText: $clipboardViewModel.editingText,
                            onSave: saveEdit,
                            onCancel: cancelEdit
                        )
                    } else {
                        emptyState
                    }

                    // Metadata Input Overlay
                    if isAddingMetadata {
                        metadataOverlay
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // MARK: - Footer
            FooterView(
                focusManager: focusManager,
                onPasteToApp: pasteToApp,
                onCopyToClipboard: copyToClipboard,
                onEdit: editEntry,
                onPin: pinEntry,
                onAddMetadata: addMetadata,
                onDelete: deleteEntry,
                onDeleteAll: deleteAllEntries,
                onDeleteMetadata: deleteMetadata,
                hasMetadata: clipboardViewModel.selectedItem?.customMetadata != nil
            )
        }
        .background(VisualEffectView().ignoresSafeArea())
        .ignoresSafeArea()
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.obsidianBorder, lineWidth: 1)
                .ignoresSafeArea()
        )
        .task {
            clipboardViewModel.startMonitoring()
            clipboardViewModel.ensureSelection()
        }
        .onChange(of: clipboardViewModel.history) { _ in clipboardViewModel.ensureSelection() }
        .onChange(of: clipboardViewModel.searchText) { _ in clipboardViewModel.ensureSelection() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.luminaTextSecondary.opacity(0.5))
            Text("No clips found")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(.luminaTextSecondary)
        }
    }

    // MARK: - Actions
    
    private func pasteToApp() {
        guard let item = clipboardViewModel.selectedItem else { return }
        
        // 1. Copy to pasteboard
        clipboardViewModel.copyToPasteboard(item: item)
        // 2. Switch Focus Explicitly
        if let previousApp = focusManager.previousApp {
            previousApp.activate(options: .activateIgnoringOtherApps)
        } else {
            NSApplication.shared.hide(nil)
        }
    }
    
    private func copyToClipboard() {
        guard let item = clipboardViewModel.selectedItem else { return }
        clipboardViewModel.copyToPasteboard(item: item)
    }
    
    private func editEntry() {
        guard let item = clipboardViewModel.selectedItem else { return }
        clipboardViewModel.isEditing = true
        clipboardViewModel.editingText = item.textRepresentation
    }
    
    private func saveEdit() {
        guard let item = clipboardViewModel.selectedItem else { return }
        clipboardViewModel.updateItem(id: item.id, newText: clipboardViewModel.editingText)
        clipboardViewModel.isEditing = false
    }
    
    private func cancelEdit() {
        clipboardViewModel.isEditing = false
    }
    
    private func pinEntry() {
        guard let item = clipboardViewModel.selectedItem else { return }
        clipboardViewModel.togglePin(for: item.id)
    }
    
    private func addMetadata() {
        guard let item = clipboardViewModel.selectedItem else { return }
        metadataInput = item.customMetadata ?? ""
        isAddingMetadata = true
    }
    
    private func saveMetadata() {
        guard let item = clipboardViewModel.selectedItem else { return }
        clipboardViewModel.updateItemMetadata(id: item.id, metadata: metadataInput.isEmpty ? nil : metadataInput)
        isAddingMetadata = false
    }
    
    private func deleteMetadata() {
        guard let item = clipboardViewModel.selectedItem else { return }
        clipboardViewModel.updateItemMetadata(id: item.id, metadata: nil)
    }
    
    private func deleteEntry() {
        guard let item = clipboardViewModel.selectedItem else { return }
        clipboardViewModel.deleteItem(id: item.id)
    }
    
    private func deleteAllEntries() {
        clipboardViewModel.deleteAll()
    }
    
    // MARK: - Metadata Overlay
    private var metadataOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isAddingMetadata = false
                }

            VStack(spacing: 16) {
                Text(metadataInput.isEmpty ? "Add Metadata" : "Edit Metadata")
                    .font(.custom("Roboto", size: 16))
                    .fontWeight(.bold)
                    .foregroundColor(.luminaTextPrimary)

                TextField("Enter metadata...", text: $metadataInput)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.obsidianSurface)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.obsidianBorder, lineWidth: 1)
                    )
                    .foregroundColor(.luminaTextPrimary)
                    .frame(width: 250)
                    .onSubmit {
                        saveMetadata()
                    }

                HStack(spacing: 12) {
                    Button("Cancel") {
                        isAddingMetadata = false
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.luminaTextSecondary)

                    Button("Save") {
                        saveMetadata()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .cornerRadius(6)
                }
            }
            .padding(24)
            .background(Color.obsidianBackground)
            .cornerRadius(12)
            .shadow(radius: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.obsidianBorder, lineWidth: 1)
            )
        }
    }
}
