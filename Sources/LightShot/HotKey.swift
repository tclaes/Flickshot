import Carbon
import Foundation

/// Global hotkey via Carbon's RegisterEventHotKey. Unlike an NSEvent global
/// monitor, this needs no Accessibility permission and swallows the keystroke.
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandlerInstalled = false

    private var ref: EventHotKeyRef?
    private let id: UInt32

    /// Returns nil when the combination is already taken by another app.
    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        HotKey.installEventHandlerIfNeeded()
        id = HotKey.nextID
        HotKey.nextID += 1

        let hotKeyID = EventHotKeyID(signature: OSType(0x4C534854), id: id) // 'LSHT'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, ref != nil else { return nil }
        HotKey.handlers[id] = handler
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.handlers[id] = nil
    }

    private static func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr, let handler = HotKey.handlers[hotKeyID.id] else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async(execute: handler)
            return noErr
        }, 1, &spec, nil, nil)
    }
}
