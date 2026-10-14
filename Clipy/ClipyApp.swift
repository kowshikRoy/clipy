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
    @StateObject private var permissionMonitor = PermissionMonitor()
    
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView(settings: appSettings, focusManager: appFocusManager, permissionMonitor: permissionMonitor)
                .environment(\.locale, appSettings.resolvedLocale)
                .frame(width: 1000, height: 600)
                .background(MainWindowConfigurator())
                .onAppear {
                    setupHotKey()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    if let window = Self.mainAppWindow {
                        Self.configure(window: window)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    NSApplication.shared.hide(nil)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 600)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        
        MenuBarExtra("Clipy", systemImage: "paperclip") {
            Button("Show Clipy") {
                toggleAppVisibility()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            
            Button("Settings") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)
             
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        
        WindowGroup("Settings", id: "settings") {
            SettingsView(settings: appSettings)
                .environment(\.locale, appSettings.resolvedLocale)
                .frame(minWidth: 650, minHeight: 420)
        }
        .windowResizability(.contentSize)
    }
    
    static var mainAppWindow: NSWindow? {
        NSApplication.shared.windows.first { window in
            let className = NSStringFromClass(type(of: window))
            return !className.contains("StatusBar")
                && !className.contains("Popup")
                && window.identifier?.rawValue != "settings"
                && window.contentView != nil
        }
    }

    static func configure(window: NSWindow) {
        let fixedSize = NSSize(width: 1000, height: 600)
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.remove(.resizable)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.minSize = fixedSize
        window.maxSize = fixedSize
        window.contentMinSize = fixedSize
        window.contentMaxSize = fixedSize
        if window.frame.width != 1000 || window.frame.height != 600 {
            window.setFrame(NSRect(origin: window.frame.origin, size: fixedSize), display: true)
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
            if let window = Self.mainAppWindow {
                Self.configure(window: window)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

private struct MainWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                ClipyApp.configure(window: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                ClipyApp.configure(window: window)
            }
        }
    }
}
