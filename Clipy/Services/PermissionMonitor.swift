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
}
