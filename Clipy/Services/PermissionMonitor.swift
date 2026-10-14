import SwiftUI
import AppKit
import ApplicationServices
import Combine

class PermissionMonitor: ObservableObject {
    @Published var isTrusted: Bool = false
    private var timer: Timer?

    init() {
        let trusted = checkPermission()
        if !trusted {
            registerInAccessibilityList()
        }
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

    @discardableResult
    func checkPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let currentStatus = AXIsProcessTrustedWithOptions(options)
        print("[Debug] Monitor Check: \(currentStatus)")
        
        if isTrusted != currentStatus {
            if Thread.isMainThread {
                self.isTrusted = currentStatus
            } else {
                DispatchQueue.main.async {
                    self.isTrusted = currentStatus
                }
            }
        }
        return currentStatus
    }

    /// Ensures Clipy appears in System Settings -> Privacy & Security -> Accessibility on launch
    /// without resetting/deleting any existing TCC entry.
    private func registerInAccessibilityList() {
        DispatchQueue.global(qos: .userInitiated).async {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            let status = AXIsProcessTrustedWithOptions(options)
            DispatchQueue.main.async {
                self.isTrusted = status
            }

            // Wait ~1.0s so universalAccessAuthWarn finishes TCCAccessSetForBundleIdWithOptions()
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {
                Self.dismissSystemAuthAlert()
            }
        }
    }

    func openAccessibilitySettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.matrixcode.Clipy"
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Reset any stale CDHash from an older build so the current binary is registered cleanly
            let resetTask = Process()
            resetTask.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            resetTask.arguments = ["reset", "Accessibility", bundleID]
            try? resetTask.run()
            resetTask.waitUntilExit()

            // 2. Prompt TCC registration so universalAccessAuthWarn adds Clipy to the Accessibility list
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            let status = AXIsProcessTrustedWithOptions(options)
            
            // 3. Open System Settings -> Privacy & Security -> Accessibility
            DispatchQueue.main.async {
                self.isTrusted = status
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            
            // 4. Dismiss the redundant background alert after TCC registration completes (~1.0s)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {
                Self.dismissSystemAuthAlert()
            }
        }
    }

    private static func dismissSystemAuthAlert() {
        let dismissTask = Process()
        dismissTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        dismissTask.arguments = ["universalAccessAuthWarn"]
        dismissTask.standardOutput = FileHandle.nullDevice
        dismissTask.standardError = FileHandle.nullDevice
        try? dismissTask.run()
    }
}
