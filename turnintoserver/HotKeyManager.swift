import Carbon
import Foundation

final class HotKeyManager {
    private enum HotKey: UInt32 {
        case toggleServerMode = 1
        case toggleBatteryServerMode = 2
    }

    private static let signature = fourCharCode("ttsv")
    private static let modifierFlags = UInt32(cmdKey | optionKey | controlKey)

    private let onToggleServerMode: @MainActor () async -> Void
    private let onToggleBatteryServerMode: @MainActor () async -> Void
    private var eventHandler: EventHandlerRef?
    private var toggleServerModeHotKey: EventHotKeyRef?
    private var toggleBatteryServerModeHotKey: EventHotKeyRef?

    init(
        onToggleServerMode: @escaping @MainActor () async -> Void,
        onToggleBatteryServerMode: @escaping @MainActor () async -> Void
    ) {
        self.onToggleServerMode = onToggleServerMode
        self.onToggleBatteryServerMode = onToggleBatteryServerMode
    }

    deinit {
        stop()
    }

    func start() {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleHotKeyEvent,
            1,
            &eventType,
            userData,
            &eventHandler
        )
        guard status == noErr else {
            eventHandler = nil
            return
        }

        registerHotKey(.toggleServerMode, keyCode: UInt32(kVK_ANSI_O), storage: &toggleServerModeHotKey)
        registerHotKey(
            .toggleBatteryServerMode,
            keyCode: UInt32(kVK_ANSI_P),
            storage: &toggleBatteryServerModeHotKey
        )
    }

    func stop() {
        if let toggleServerModeHotKey {
            UnregisterEventHotKey(toggleServerModeHotKey)
            self.toggleServerModeHotKey = nil
        }

        if let toggleBatteryServerModeHotKey {
            UnregisterEventHotKey(toggleBatteryServerModeHotKey)
            self.toggleBatteryServerModeHotKey = nil
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func registerHotKey(
        _ hotKey: HotKey,
        keyCode: UInt32,
        storage: inout EventHotKeyRef?
    ) {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: hotKey.rawValue)
        let status = RegisterEventHotKey(
            keyCode,
            Self.modifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &storage
        )

        if status != noErr {
            storage = nil
        }
    }

    private func handleHotKey(id: UInt32) -> OSStatus {
        guard let hotKey = HotKey(rawValue: id) else {
            return OSStatus(eventNotHandledErr)
        }

        Task { @MainActor in
            switch hotKey {
            case .toggleServerMode:
                await onToggleServerMode()
            case .toggleBatteryServerMode:
                await onToggleBatteryServerMode()
            }
        }

        return noErr
    }

    private static let handleHotKeyEvent: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID(signature: 0, id: 0)
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == HotKeyManager.signature else {
            return OSStatus(eventNotHandledErr)
        }

        let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        return manager.handleHotKey(id: hotKeyID.id)
    }

    private static func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { code, character in
            (code << 8) + OSType(character)
        }
    }
}
