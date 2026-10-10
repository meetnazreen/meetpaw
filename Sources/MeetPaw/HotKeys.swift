import Carbon
import AppKit

/// Registers global ⌘⇧ hotkeys (work from any app) and calls `onFire` with the
/// hotkey id when pressed.
final class HotKeys {
    private var refs: [EventHotKeyRef?] = []
    private let onFire: (Int) -> Void

    init(onFire: @escaping (Int) -> Void) {
        self.onFire = onFire
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            Unmanaged<HotKeys>.fromOpaque(userData!).takeUnretainedValue().onFire(Int(hkID.id))
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)

        register(id: 1, keyCode: UInt32(kVK_ANSI_M))   // Google Meet
        register(id: 2, keyCode: UInt32(kVK_ANSI_Z))   // Zoom
        register(id: 3, keyCode: UInt32(kVK_ANSI_T))   // Teams
    }

    private func register(id: UInt32, keyCode: UInt32) {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x4D504157), id: id)   // 'MPAW'
        RegisterEventHotKey(keyCode, UInt32(cmdKey | shiftKey), hkID,
                            GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }
}
