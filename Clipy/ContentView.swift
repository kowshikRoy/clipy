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
        .onAppear {
            clipboardViewModel.resetToDefault()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            clipboardViewModel.resetToDefault()
        }
        .alert("Accessibility Permission Needed", isPresented: $showPermissionAlert) {
            Button("Reset Cache & Open Settings") {
                permissionMonitor.resetAndRequestPermission()
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Clipy needs Accessibility permission to simulate Cmd+V and paste automatically.\n\n⚠️ WHY TOGGLING OFF/ON FAILED:\nWhen you rebuild an ad-hoc signed app, macOS stores stale binary cdhashes in TCC. Toggling the checkbox in Settings only toggled the old hash.\n\nClicking 'Reset Cache & Open Settings' above clears the stale cache automatically so macOS prompts cleanly for this new build.\n\n(We have already copied your selection to the clipboard so you can press Cmd+V manually!)")
        }
        .onExitCommand {
            NSApplication.shared.hide(nil)
        }
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
