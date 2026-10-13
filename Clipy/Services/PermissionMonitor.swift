import SwiftUI
import AppKit
import ApplicationServices
import Combine

class PermissionMonitor: ObservableObject {
    @Published var isTrusted: Bool = false
    private var timer: Timer?

    init() {
        checkPermission()
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func checkPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let currentStatus = AXIsProcessTrustedWithOptions(options)
        print("[Debug] Monitor Check: \(currentStatus)")
        
        if isTrusted != currentStatus {
            DispatchQueue.main.async {
                self.isTrusted = currentStatus
            }
        }
    }

    func openAccessibilitySettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.matrixcode.Clipy"
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Reset any stale TCC signature from previous builds so toggling in System Settings works
            let resetTask = Process()
            resetTask.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            resetTask.arguments = ["reset", "Accessibility", bundleID]
            try? resetTask.run()
            resetTask.waitUntilExit()
            
            // 2. Trigger TCC registration so Clipy appears in the System Settings Accessibility list
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            let status = AXIsProcessTrustedWithOptions(options)
            
            // 3. Dismiss the redundant system popup modal so ONLY System Settings opens
            for delay in [0.1, 0.25, 0.5] {
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                    let dismissTask = Process()
                    dismissTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                    dismissTask.arguments = ["-9", "universalAccessAuthWarn"]
                    dismissTask.standardOutput = FileHandle.nullDevice
                    dismissTask.standardError = FileHandle.nullDevice
                    try? dismissTask.run()
                }
            }
            
            DispatchQueue.main.async {
                self.isTrusted = status
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
