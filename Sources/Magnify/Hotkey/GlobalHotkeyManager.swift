import Carbon
import Foundation

final class GlobalHotkeyManager {
    private enum Constants {
        static let hotKeyIdentifier: UInt32 = 1
        static let hotKeySignature: OSType = 0x4D41474E // "MAGN"
    }

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    var onHotKeyPressed: (() -> Void)?

    func register() {
        installEventHandlerIfNeeded()
        unregister()

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = Constants.hotKeySignature
        hotKeyID.id = Constants.hotKeyIdentifier

        let modifiers = UInt32(cmdKey) | UInt32(optionKey)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_M),
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    deinit {
        unregister()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
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

                guard status == noErr else {
                    return status
                }

                if hotKeyID.signature == Constants.hotKeySignature && hotKeyID.id == Constants.hotKeyIdentifier {
                    manager.onHotKeyPressed?()
                }

                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }
}
