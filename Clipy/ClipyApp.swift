//
//  ClipyApp.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI
import AppKit

@main
struct ClipyApp: App {
    @StateObject private var appSettings = AppSettings()
    @StateObject private var appFocusManager = AppFocusManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView(settings: appSettings, focusManager: appFocusManager)
                .frame(width: 1000, height: 600)
                .onAppear {
                    if let window = NSApplication.shared.windows.first {
                        window.styleMask.insert(.fullSizeContentView)
                        window.styleMask.remove(.resizable) // Disable resizing
                        window.titlebarAppearsTransparent = true
                        window.titleVisibility = .hidden
                        window.standardWindowButton(.closeButton)?.isHidden = true
                        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                        window.standardWindowButton(.zoomButton)?.isHidden = true
                        window.isMovableByWindowBackground = true
                        window.backgroundColor = .clear
                        window.isOpaque = false
                    }
                }
                .onAppear {
                    setupHotKey()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    NSApplication.shared.hide(nil)
                }
        }
        .windowStyle(.hiddenTitleBar)
        
        Settings {
            SettingsView(settings: appSettings)
                .frame(width: 500, height: 400)
        }
    }
    
    private func setupHotKey() {
        let manager = HotKeyManager.shared
        
        // Initial registration
        manager.registerHotKey(keyCode: UInt32(appSettings.hotkeyKeyCode), modifiers: UInt32(appSettings.hotkeyModifiers))
        
        // Callback
        manager.onHotKeyPressed = {
            toggleAppVisibility()
        }
    }
    
    private func toggleAppVisibility() {
        if NSApplication.shared.isActive {
             NSApplication.shared.hide(nil)
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
            // Ensure window is visible if it was closed
            if let window = NSApplication.shared.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
