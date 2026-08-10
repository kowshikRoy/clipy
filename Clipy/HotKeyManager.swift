import Cocoa
import Carbon

class HotKeyManager {
    static let shared = HotKeyManager()
    
    // Store the event handler reference to keep it alive
    private var eventHandler: EventHandlerRef?
    var hotKeyRef: EventHotKeyRef?
    
    // Callback action
    var onHotKeyPressed: (() -> Void)?
    
    private init() {
        installEventHandler()
    }
    
    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handleHotKey()
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
    }
    
    private func handleHotKey() {
        DispatchQueue.main.async { [weak self] in
            self?.onHotKeyPressed?()
        }
    }
    
    func registerHotKey(keyCode: UInt32, modifiers: UInt32) {
        // Unregister existing if any
        unregisterHotKey()
        
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C5059), id: 1) // CLPY
        
        var status = noErr
        status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status != noErr {
            print("Failed to register hotkey: \(status)")
        }
    }
    
    func unregisterHotKey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
    
    deinit {
        unregisterHotKey()
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
