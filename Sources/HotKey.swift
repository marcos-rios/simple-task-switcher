import Carbon.HIToolbox

/// A global hotkey registered with Carbon's RegisterEventHotKey.
/// Public API, needs no permissions, and consumes the keystroke (the frontmost app never sees it).
@MainActor
final class HotKey {
    /// Four-char code 'STSW' identifying our hotkeys inside the Carbon event.
    nonisolated static let signature: OSType = 0x5354_5357

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        // Pass `self` to the C callback as a raw pointer. Unretained: the HotKey must outlive
        // the registration (AppDelegate keeps it for the whole app lifetime).
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler,
                                                1, &eventType, userData, &handlerRef)
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: HotKey.signature, id: 1)
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                                 GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registerStatus == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            return nil
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    fileprivate func fire() {
        action()
    }
}

/// C callback invoked by Carbon. It cannot capture context, so `self` arrives via `userData`.
/// Must be nonisolated: a C function pointer cannot carry actor isolation.
nonisolated private func hotKeyEventHandler(_ nextHandler: EventHandlerCallRef?,
                                            _ event: EventRef?,
                                            _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    let receivedID = hotKeyID // copy to an immutable value
    guard status == noErr, receivedID.signature == HotKey.signature else {
        return OSStatus(eventNotHandledErr)
    }

    // Convert the raw pointer back to the object *before* entering the isolated closure
    // (a raw pointer is not Sendable; the MainActor class is).
    let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
    // Carbon dispatches application-target events on the main thread.
    MainActor.assumeIsolated {
        hotKey.fire()
    }
    return noErr
}
