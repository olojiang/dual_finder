import AppKit
import Carbon.HIToolbox
import DualFinderCore

final class GlobalShowWindowHotkey: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onHotKey: @Sendable () -> Void
    private let store: ShowWindowHotkeyStore
    private let hotKeyID = UInt32.random(in: 1...UInt32.max)

    init(store: ShowWindowHotkeyStore = ShowWindowHotkeyStore(), onHotKey: @escaping @Sendable () -> Void) {
        self.store = store
        self.onHotKey = onHotKey
    }

    @discardableResult
    func install() -> Bool {
        remove()
        let binding = store.binding()

        var eventType = EventTypeSpec(
            eventClass: UInt32(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installStatus == noErr else { return false }

        let eventHotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: hotKeyID
        )
        let registerStatus = RegisterEventHotKey(
            UInt32(binding.keyCode),
            Self.carbonModifiers(for: binding),
            eventHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            remove()
            return false
        }
        return true
    }

    private static func carbonModifiers(for binding: ShowWindowHotkeyBinding) -> UInt32 {
        var modifiers: UInt32 = 0
        if binding.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if binding.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if binding.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if binding.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    func remove() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit {
        remove()
    }

    private static let hotKeySignature: OSType = {
        var value: UInt32 = 0
        for byte in [UInt8(ascii: "D"), UInt8(ascii: "F"), UInt8(ascii: "N"), UInt8(ascii: "D")] {
            value = (value << 8) + UInt32(byte)
        }
        return OSType(value)
    }()

    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let userData else { return OSStatus(eventNotHandledErr) }
        guard GetEventKind(event) == UInt32(kEventHotKeyPressed) else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        let owner = Unmanaged<GlobalShowWindowHotkey>.fromOpaque(userData).takeUnretainedValue()
        guard status == noErr, hotKeyID.signature == hotKeySignature, hotKeyID.id == owner.hotKeyID else {
            return OSStatus(eventNotHandledErr)
        }

        DispatchQueue.main.async {
            owner.onHotKey()
        }
        return noErr
    }
}
