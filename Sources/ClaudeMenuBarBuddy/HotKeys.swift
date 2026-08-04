import Carbon.HIToolbox

// Global approval shortcuts: ⌘⏎ = Allow, ⇧⌘⏎ = Deny.
//
// Carbon RegisterEventHotKey rather than a CGEventTap: it needs no
// Accessibility/Input Monitoring permission. The hotkeys are registered only
// while a request is actually pending, so the rest of the time ⌘⏎ still
// reaches Slack/Mail/whatever app is frontmost.
//
// A global hotkey is the only viable path here: the approval card is a
// non-activating panel that never becomes key (by design — approve without
// leaving the terminal), so a window-local keyEquivalent would never fire.
final class ApprovalHotKeys {
    var onAllow: (() -> Void)?
    var onDeny: (() -> Void)?
    var onAlwaysAllow: (() -> Void)?

    private var allowRef: EventHotKeyRef?
    private var denyRef: EventHotKeyRef?
    private var alwaysRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x43425544 // 'CBUD'

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let hotKeys = Unmanaged<ApprovalHotKeys>.fromOpaque(userData).takeUnretainedValue()
            if hotKeyID.id == 1 { hotKeys.onAllow?() }
            else if hotKeyID.id == 2 { hotKeys.onDeny?() }
            else if hotKeyID.id == 3 { hotKeys.onAlwaysAllow?() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    func enable() {
        guard allowRef == nil else { return }
        RegisterEventHotKey(UInt32(kVK_Return), UInt32(cmdKey),
                            EventHotKeyID(signature: Self.signature, id: 1),
                            GetEventDispatcherTarget(), 0, &allowRef)
        RegisterEventHotKey(UInt32(kVK_Return), UInt32(cmdKey | shiftKey),
                            EventHotKeyID(signature: Self.signature, id: 2),
                            GetEventDispatcherTarget(), 0, &denyRef)
        RegisterEventHotKey(UInt32(kVK_Return), UInt32(cmdKey | optionKey),
                            EventHotKeyID(signature: Self.signature, id: 3),
                            GetEventDispatcherTarget(), 0, &alwaysRef)
    }

    func disable() {
        if let ref = allowRef { UnregisterEventHotKey(ref); allowRef = nil }
        if let ref = denyRef { UnregisterEventHotKey(ref); denyRef = nil }
        if let ref = alwaysRef { UnregisterEventHotKey(ref); alwaysRef = nil }
    }
}
