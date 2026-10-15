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
    
    @State private var showPermissionAlert = false
    
    // Metadata State for Dialog
    @State private var isAddingMetadata = false
    @State private var metadataInput = ""
    @FocusState private var isMetadataFocused: Bool

    @ObservedObject var permissionMonitor: PermissionMonitor

    init(settings: AppSettings, focusManager: AppFocusManager, permissionMonitor: PermissionMonitor) {
        self.appSettings = settings
        self.focusManager = focusManager
        self.permissionMonitor = permissionMonitor
        _clipboardViewModel = StateObject(wrappedValue: ClipboardViewModel(settings: settings))
    }

    var body: some View {
        let selectedItem = clipboardViewModel.selectedItem
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // MARK: - List View (Left)
                ClipboardListView(viewModel: clipboardViewModel, permissionMonitor: permissionMonitor, onPaste: pasteToApp)
                    .frame(width: 320)
                    .background(Color.obsidianBackground.opacity(0.6))
                
                Rectangle()
                    .fill(Color.obsidianBorder)
                    .frame(width: 1)
                    .ignoresSafeArea(edges: .vertical)
                
                // MARK: - Detail Stage (Right)
                ZStack {
                    Color.obsidianBackground.opacity(0.6).ignoresSafeArea()
                    
                    if let selectedItem {
                        DetailStageView(
                            item: selectedItem,
                            isEditing: $clipboardViewModel.isEditing,
                            editingText: $clipboardViewModel.editingText,
                            isEnriching: clipboardViewModel.enrichingItemIDs.contains(selectedItem.id),
                            onSave: saveEdit,
                            onCancel: cancelEdit,
                            onOpenURL: openSelectedURL,
                            onCopyOCRText: { text in
                                clipboardViewModel.copyPlainText(text)
                            }
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
            .ignoresSafeArea(edges: .top)

            // MARK: - Footer
            FooterView(
                focusManager: focusManager,
                permissionMonitor: permissionMonitor,
                onPasteToApp: pasteToApp,
                onCopyToClipboard: copyToClipboard,
                onEdit: editEntry,
                onPin: pinEntry,
                onAddMetadata: addMetadata,
                onDelete: deleteEntry,
                onDeleteAll: deleteAllEntries,
                onDeleteMetadata: deleteMetadata,
                hasMetadata: selectedItem?.customMetadata != nil,
                isPinned: selectedItem?.isPinned ?? false,
                hasURL: selectedItem?.hasLink ?? false,
                onOpenURL: openSelectedURL
            )
        }
        .background(
            ZStack {
                VisualEffectView().ignoresSafeArea()
                shortcutButtons
            }
        )
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
        .onAppear {
            clipboardViewModel.resetToDefault()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            clipboardViewModel.resetToDefault()
        }
        .alert("Enable Auto-Paste", isPresented: $showPermissionAlert) {
            Button("Open System Settings") {
                permissionMonitor.openAccessibilitySettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("To paste directly into your active app, please enable Clipy in System Settings → Privacy & Security → Accessibility.\n\nYour selection has already been copied to the clipboard, so you can press ⌘V right now.")
        }
        .onExitCommand {
            NSApplication.shared.hide(nil)
        }
    }

    @ViewBuilder
    private var shortcutButtons: some View {
        Group {
            Button("", action: copyToClipboard)
                .keyboardShortcut(.return, modifiers: [.command])
            Button("", action: pinEntry)
                .keyboardShortcut("p", modifiers: [.command])
            Button("", action: editEntry)
                .keyboardShortcut("e", modifiers: [.command])
            Button("", action: openSelectedURL)
                .keyboardShortcut("o", modifiers: [.command])
            Button("", action: addMetadata)
                .keyboardShortcut("m", modifiers: [.command])
            
            ForEach(1...9, id: \.self) { index in
                Button("") {
                    pasteItemAtIndex(index - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: [.command])
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
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
    
    private func pasteItemAtIndex(_ index: Int) {
        let items = clipboardViewModel.visualHistory
        guard index >= 0 && index < items.count else { return }
        clipboardViewModel.selectedItemID = items[index].id
        pasteToApp()
    }
    
    private func openSelectedURL() {
        guard let item = clipboardViewModel.selectedItem else { return }
        clipboardViewModel.openURL(for: item)
    }
    
    private func pasteToApp() {
        print("[Debug] pasteToApp called")
        guard let item = clipboardViewModel.selectedItem else {
            print("[Debug] No item selected")
            return
        }
        
        // Check permissions via monitor
        permissionMonitor.checkPermission()
        
        // ALWAYS copy to pasteboard first so the user's selection is available immediately!
        clipboardViewModel.copyToPasteboard(item: item)
        print("[Debug] Copied item to pasteboard")
        
        if !permissionMonitor.isTrusted {
            print("[Debug] showing permission alert (fallback: copied to pasteboard)")
            // Hide Clipy so the user can immediately press Cmd+V in their app!
            NSApplication.shared.hide(nil)
            showPermissionAlert = true
            return
        }
        
        // 2. Hide Clipy (Return focus to previous app implicitly)
        NSApplication.shared.hide(nil)
        print("[Debug] App hidden, waiting 0.2s...")
        
        // 3. Simulate Cmd+V using CGEvent
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            print("[Debug] Executing paste...")
            self.clipboardViewModel.paste()
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
                    .focused($isMetadataFocused)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isMetadataFocused = true
                        }
                    }
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
