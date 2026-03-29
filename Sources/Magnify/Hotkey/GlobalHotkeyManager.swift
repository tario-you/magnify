import Carbon
import Foundation

final class GlobalHotkeyManager {
    private enum Constants {
        static let hotKeySignature: OSType = 0x4D41474E // "MAGN"
    }

    private enum HotKeyIdentifier: UInt32 {
        case modeToggle = 1
        case editModeToggle = 2
        case zoomToggle = 3
        case zoomOut = 4
        case zoomIn = 5
    }

    private struct HotKeyRegistration {
        let identifier: HotKeyIdentifier
        let keyCode: UInt32
        let modifiers: UInt32
    }

    private var hotKeyRefs: [HotKeyIdentifier: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?

    var onModeTogglePressed: (() -> Void)?
    var onEditModeTogglePressed: (() -> Void)?
    var onZoomTogglePressed: (() -> Void)?
    var onZoomOutPressed: (() -> Void)?
    var onZoomInPressed: (() -> Void)?

    func register() {
        installEventHandlerIfNeeded()
        unregister()

        let presentationModifiers = UInt32(cmdKey) | UInt32(optionKey)
        let zoomModifiers = UInt32(optionKey)
        let zoomInModifiers = UInt32(optionKey)
        let registrations = [
            HotKeyRegistration(identifier: .modeToggle, keyCode: UInt32(kVK_ANSI_M), modifiers: presentationModifiers),
            HotKeyRegistration(identifier: .editModeToggle, keyCode: UInt32(kVK_ANSI_E), modifiers: presentationModifiers),
            HotKeyRegistration(identifier: .zoomToggle, keyCode: UInt32(kVK_ANSI_8), modifiers: zoomModifiers),
            HotKeyRegistration(identifier: .zoomOut, keyCode: UInt32(kVK_ANSI_Minus), modifiers: zoomModifiers),
            HotKeyRegistration(identifier: .zoomIn, keyCode: UInt32(kVK_ANSI_Equal), modifiers: zoomInModifiers)
        ]

        for registration in registrations {
            var hotKeyID = EventHotKeyID()
            hotKeyID.signature = Constants.hotKeySignature
            hotKeyID.id = registration.identifier.rawValue

            var hotKeyRef: EventHotKeyRef?
            RegisterEventHotKey(
                registration.keyCode,
                registration.modifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &hotKeyRef
            )

            if let hotKeyRef {
                hotKeyRefs[registration.identifier] = hotKeyRef
            }
        }
    }

    func unregister() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }

        hotKeyRefs.removeAll()
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

                guard hotKeyID.signature == Constants.hotKeySignature,
                      let identifier = HotKeyIdentifier(rawValue: hotKeyID.id) else {
                    return noErr
                }

                switch identifier {
                case .modeToggle:
                    manager.onModeTogglePressed?()
                case .editModeToggle:
                    manager.onEditModeTogglePressed?()
                case .zoomToggle:
                    manager.onZoomTogglePressed?()
                case .zoomOut:
                    manager.onZoomOutPressed?()
                case .zoomIn:
                    manager.onZoomInPressed?()
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
