import AppKit
import Carbon.HIToolbox

/// Đăng ký global hotkey bằng Carbon `RegisterEventHotKey`. Ưu điểm so với
/// NSEvent global monitor: hoạt động kể cả khi app không active và KHÔNG cần
/// quyền Accessibility. Mỗi hotkey gắn một closure chạy trên main actor.
@MainActor
final class HotKeyCenter {
    private var refs: [EventHotKeyRef?] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    /// Carbon modifier mask cho ⌥ (Option) đơn.
    static let opt = UInt32(optionKey)

    /// Đăng ký một hotkey. Trả về false nếu hệ thống từ chối (đã bị app khác giữ).
    @discardableResult
    func register(keyCode: Int, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID; nextID += 1
        var ref: EventHotKeyRef?
        // signature 'JNCH' — nhận diện hotkey của app này.
        let hkID = EventHotKeyID(signature: 0x4A4E4348, id: id)
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return false }
        refs.append(ref)
        handlers[id] = action
        return true
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            let id = hkID.id
            Task { @MainActor in center.handlers[id]?() }
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }

    deinit {
        for ref in refs { if let ref { UnregisterEventHotKey(ref) } }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
