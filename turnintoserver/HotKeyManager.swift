import Carbon
import AppKit
import Foundation

extension Notification.Name {
    static let turnIntoServerHotKeysDidChange = Notification.Name("turnIntoServerHotKeysDidChange")
    static let turnIntoServerHotKeyRecordingDidStart = Notification.Name("turnIntoServerHotKeyRecordingDidStart")
    static let turnIntoServerHotKeyRecordingDidEnd = Notification.Name("turnIntoServerHotKeyRecordingDidEnd")
}

struct HotKeyShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifierFlags: UInt32
    let keyDisplay: String

    static let defaultModifierFlags = UInt32(cmdKey | optionKey | controlKey)
    static let defaultServerMode = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_O),
        modifierFlags: defaultModifierFlags,
        keyDisplay: "O"
    )
    static let defaultBatteryMode = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_P),
        modifierFlags: defaultModifierFlags,
        keyDisplay: "P"
    )

    var displayString: String {
        var parts: [String] = []
        if modifierFlags & UInt32(controlKey) != 0 {
            parts.append("⌃")
        }
        if modifierFlags & UInt32(optionKey) != 0 {
            parts.append("⌥")
        }
        if modifierFlags & UInt32(shiftKey) != 0 {
            parts.append("⇧")
        }
        if modifierFlags & UInt32(cmdKey) != 0 {
            parts.append("⌘")
        }

        return parts.joined() + keyDisplay
    }

    init(keyCode: UInt32, modifierFlags: UInt32, keyDisplay: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.keyDisplay = keyDisplay
    }

    init?(event: NSEvent) {
        let modifierFlags = Self.carbonModifierFlags(from: event.modifierFlags)
        guard modifierFlags != 0 else {
            return nil
        }

        let keyDisplay = Self.keyDisplay(for: event)
        guard !keyDisplay.isEmpty else {
            return nil
        }

        self.keyCode = UInt32(event.keyCode)
        self.modifierFlags = modifierFlags
        self.keyDisplay = keyDisplay
    }

    static func load(
        defaultsKey: String,
        default defaultShortcut: HotKeyShortcut,
        defaults: UserDefaults = .standard
    ) -> HotKeyShortcut {
        guard let data = defaults.data(forKey: defaultsKey),
              let shortcut = try? JSONDecoder().decode(HotKeyShortcut.self, from: data) else {
            return defaultShortcut
        }

        return shortcut
    }

    func save(defaultsKey: String, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else {
            return
        }

        defaults.set(data, forKey: defaultsKey)
        NotificationCenter.default.post(name: .turnIntoServerHotKeysDidChange, object: nil)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: AppDefaultsKey.serverModeHotKey)
        defaults.removeObject(forKey: AppDefaultsKey.batteryModeHotKey)
        NotificationCenter.default.post(name: .turnIntoServerHotKeysDidChange, object: nil)
    }

    private static func carbonModifierFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) {
            result |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            result |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            result |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            result |= UInt32(cmdKey)
        }

        return result
    }

    private static func keyDisplay(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space:
            return "Space"
        case kVK_Return:
            return "Return"
        case kVK_Tab:
            return "Tab"
        case kVK_Delete:
            return "Delete"
        case kVK_ForwardDelete:
            return "Forward Delete"
        case kVK_LeftArrow:
            return "←"
        case kVK_RightArrow:
            return "→"
        case kVK_UpArrow:
            return "↑"
        case kVK_DownArrow:
            return "↓"
        default:
            return event.charactersIgnoringModifiers?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
        }
    }
}

final class HotKeyManager {
    private enum HotKey: UInt32 {
        case toggleServerMode = 1
        case toggleBatteryServerMode = 2
    }

    private static let signature = fourCharCode("ttsv")

    private let onToggleServerMode: @MainActor () async -> Void
    private let onToggleBatteryServerMode: @MainActor () async -> Void
    private var eventHandler: EventHandlerRef?
    private var toggleServerModeHotKey: EventHotKeyRef?
    private var toggleBatteryServerModeHotKey: EventHotKeyRef?
    private var hotKeysDidChangeObserver: NSObjectProtocol?
    private var recordingDidStartObserver: NSObjectProtocol?
    private var recordingDidEndObserver: NSObjectProtocol?
    private var isPausedForRecording = false

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

        startObservers()

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

        reloadHotKeys()
    }

    func stop() {
        unregisterHotKeys()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }

        stopObservers()
    }

    private func startObservers() {
        guard hotKeysDidChangeObserver == nil,
              recordingDidStartObserver == nil,
              recordingDidEndObserver == nil else {
            return
        }

        hotKeysDidChangeObserver = NotificationCenter.default.addObserver(
            forName: .turnIntoServerHotKeysDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadHotKeys()
        }

        recordingDidStartObserver = NotificationCenter.default.addObserver(
            forName: .turnIntoServerHotKeyRecordingDidStart,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isPausedForRecording = true
            self?.unregisterHotKeys()
        }

        recordingDidEndObserver = NotificationCenter.default.addObserver(
            forName: .turnIntoServerHotKeyRecordingDidEnd,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isPausedForRecording = false
            self?.reloadHotKeys()
        }
    }

    private func stopObservers() {
        let notificationCenter = NotificationCenter.default
        if let hotKeysDidChangeObserver {
            notificationCenter.removeObserver(hotKeysDidChangeObserver)
            self.hotKeysDidChangeObserver = nil
        }
        if let recordingDidStartObserver {
            notificationCenter.removeObserver(recordingDidStartObserver)
            self.recordingDidStartObserver = nil
        }
        if let recordingDidEndObserver {
            notificationCenter.removeObserver(recordingDidEndObserver)
            self.recordingDidEndObserver = nil
        }
    }

    private func reloadHotKeys() {
        guard !isPausedForRecording else {
            return
        }

        unregisterHotKeys()

        guard Self.hotKeysEnabled() else {
            return
        }

        let serverModeShortcut = HotKeyShortcut.load(
            defaultsKey: AppDefaultsKey.serverModeHotKey,
            default: .defaultServerMode
        )
        let batteryModeShortcut = HotKeyShortcut.load(
            defaultsKey: AppDefaultsKey.batteryModeHotKey,
            default: .defaultBatteryMode
        )

        registerHotKey(.toggleServerMode, shortcut: serverModeShortcut, storage: &toggleServerModeHotKey)
        registerHotKey(.toggleBatteryServerMode, shortcut: batteryModeShortcut, storage: &toggleBatteryServerModeHotKey)
    }

    private func unregisterHotKeys() {
        if let toggleServerModeHotKey {
            UnregisterEventHotKey(toggleServerModeHotKey)
            self.toggleServerModeHotKey = nil
        }

        if let toggleBatteryServerModeHotKey {
            UnregisterEventHotKey(toggleBatteryServerModeHotKey)
            self.toggleBatteryServerModeHotKey = nil
        }
    }

    private func registerHotKey(
        _ hotKey: HotKey,
        shortcut: HotKeyShortcut,
        storage: inout EventHotKeyRef?
    ) {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: hotKey.rawValue)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &storage
        )

        if status != noErr {
            storage = nil
        }
    }

    private static func hotKeysEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: AppDefaultsKey.hotKeysEnabled) as? Bool ?? true
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
