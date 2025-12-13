import SwiftUI
import AppKit
import Combine

class AppFocusManager: ObservableObject {
    @Published var previousApp: NSRunningApplication?
    
    private var subscribers: Set<AnyCancellable> = []
    
    init() {
        setupObservers()
    }
    
    private func setupObservers() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notification in
                self?.handleAppActivation(notification)
            }
            .store(in: &subscribers)
    }
    
    private func handleAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        
        // If the activated app is NOT Clipy (us), save it as the "previous" app.
        // When Clipy IS activated, we want to keep the one we stored just before.
        if app.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = app
        }
    }
}
