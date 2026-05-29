import Darwin
import Foundation

final class MCPControlServer {
    private struct PendingSettingChange {
        let id: String
        let token: String
        let option: String
        let title: String
        let value: SettingValue
        let currentValueForResponse: Any
        let requestedValueForResponse: Any
        let impact: String
        let stateSignature: String
        let createdAt: Date
        let expiresAt: Date
    }

    private struct PreparedSettingChange {
        let option: String
        let title: String
        let value: SettingValue
        let currentValueForResponse: Any
        let requestedValueForResponse: Any
        let impact: String
    }

    private enum SettingValue {
        case bool(Bool)
        case int(Int)
        case intArray([Int])
        case string(String)
        case hotKey(HotKeyShortcut?)
        case clearTimedServerMode
        case resetHotKeys
    }

    private struct ControlFailure: LocalizedError {
        let code: String
        let message: String

        var errorDescription: String? {
            message
        }
    }

    private weak var appState: AppState?
    private let socketPath: String
    private let queue = DispatchQueue(label: "com.qianyushi.turnintoserver.mcp-control")
    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var pendingSettingChanges: [String: PendingSettingChange] = [:]

    init(appState: AppState, socketPath: String = MCPControlServer.defaultSocketPath()) {
        self.appState = appState
        self.socketPath = socketPath
    }

    func start() {
        queue.async { [weak self] in
            self?.startListening()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.acceptSource?.cancel()
            self.acceptSource = nil

            if self.serverSocket >= 0 {
                Darwin.close(self.serverSocket)
                self.serverSocket = -1
            }

            unlink(self.socketPath)
            unlink(MCPControlServer.legacySocketPath())
        }
    }

    private static func defaultSocketPath() -> String {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("turnintoserver", isDirectory: true)

        return directory.appendingPathComponent("mcp-control.sock").path
    }

    private static func legacySocketPath() -> String {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("turnintoserver", isDirectory: true)

        return directory.appendingPathComponent("hermes-control.sock").path
    }

    private func startListening() {
        do {
            try prepareSocketDirectory()
            let fd = try makeServerSocket()
            serverSocket = fd

            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in
                self?.acceptAvailableClients()
            }
            source.setCancelHandler {
                Darwin.close(fd)
            }
            acceptSource = source
            source.resume()
        } catch {
            NSLog("turnintoserver MCP control server failed to start: \(error.localizedDescription)")
        }
    }

    private func prepareSocketDirectory() throws {
        let socketURL = URL(fileURLWithPath: socketPath)
        let directoryURL = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
        unlink(socketPath)
        unlink(Self.legacySocketPath())
    }

    private func makeServerSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ControlFailure(code: "socket_failed", message: String(cString: strerror(errno)))
        }

        do {
            var address = sockaddr_un()
            let pathBytes = Array(socketPath.utf8CString)
            let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
            guard pathBytes.count <= maxPathLength else {
                throw ControlFailure(code: "socket_path_too_long", message: "Control socket path is too long.")
            }

            address.sun_family = sa_family_t(AF_UNIX)
            let addressLength = MemoryLayout.offset(of: \sockaddr_un.sun_path)! + pathBytes.count
            #if os(macOS)
            address.sun_len = UInt8(addressLength)
            #endif

            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: maxPathLength) { destination in
                    for index in 0..<pathBytes.count {
                        destination[index] = pathBytes[index]
                    }
                }
            }

            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    Darwin.bind(fd, socketAddress, socklen_t(addressLength))
                }
            }
            guard bindResult == 0 else {
                throw ControlFailure(code: "bind_failed", message: String(cString: strerror(errno)))
            }

            chmod(socketPath, S_IRUSR | S_IWUSR)

            let flags = fcntl(fd, F_GETFL)
            if flags >= 0 {
                _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
            }

            guard listen(fd, SOMAXCONN) == 0 else {
                throw ControlFailure(code: "listen_failed", message: String(cString: strerror(errno)))
            }

            return fd
        } catch {
            Darwin.close(fd)
            unlink(socketPath)
            throw error
        }
    }

    private func acceptAvailableClients() {
        guard serverSocket >= 0 else {
            return
        }

        while true {
            let clientFD = accept(serverSocket, nil, nil)
            if clientFD >= 0 {
                handleClient(fileDescriptor: clientFD)
                continue
            }

            if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                return
            }

            return
        }
    }

    private func handleClient(fileDescriptor clientFD: Int32) {
        let flags = fcntl(clientFD, F_GETFL)
        if flags >= 0 {
            _ = fcntl(clientFD, F_SETFL, flags & ~O_NONBLOCK)
        }

        Task.detached(priority: .utility) { [weak self] in
            await self?.readRequests(from: clientFD)
        }
    }

    private func readRequests(from clientFD: Int32) async {
        defer {
            Darwin.close(clientFD)
        }

        var buffer = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = bytes.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return -1
                }
                return Darwin.read(clientFD, baseAddress, rawBuffer.count)
            }

            if bytesRead > 0 {
                buffer.append(contentsOf: bytes.prefix(bytesRead))
                while let newlineIndex = buffer.firstIndex(of: 10) {
                    let line = buffer[..<newlineIndex]
                    buffer.removeSubrange(...newlineIndex)
                    guard !line.isEmpty else {
                        continue
                    }

                    let response = await processRequest(Data(line))
                    write(response, to: clientFD)
                }
            } else if bytesRead == 0 {
                if !buffer.isEmpty {
                    let response = await processRequest(buffer)
                    write(response, to: clientFD)
                }
                return
            } else if errno != EINTR {
                return
            }
        }
    }

    private func write(_ data: Data, to fileDescriptor: Int32) {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            var written = 0
            while written < rawBuffer.count {
                let result = Darwin.write(
                    fileDescriptor,
                    baseAddress.advanced(by: written),
                    rawBuffer.count - written
                )
                if result > 0 {
                    written += result
                } else if errno != EINTR {
                    return
                }
            }
        }
    }

    private func processRequest(_ requestData: Data) async -> Data {
        var requestID: Any = NSNull()
        do {
            guard let object = try JSONSerialization.jsonObject(with: requestData) as? [String: Any] else {
                return responseData(id: NSNull(), ok: false, data: nil, error: errorJSON(
                    code: "invalid_request",
                    message: "Request must be a JSON object."
                ))
            }

            requestID = object["id"] ?? NSNull()
            guard let action = object["action"] as? String else {
                return responseData(id: requestID, ok: false, data: nil, error: errorJSON(
                    code: "missing_action",
                    message: "Request action is required."
                ))
            }

            let params = object["params"] as? [String: Any] ?? [:]
            let data = try await handleAction(action, params: params)
            return responseData(id: requestID, ok: true, data: data, error: nil)
        } catch let failure as ControlFailure {
            return responseData(id: requestID, ok: false, data: nil, error: errorJSON(
                code: failure.code,
                message: failure.message
            ))
        } catch {
            return responseData(id: requestID, ok: false, data: nil, error: errorJSON(
                code: "internal_error",
                message: error.localizedDescription
            ))
        }
    }

    @MainActor
    private func handleAction(_ action: String, params: [String: Any]) async throws -> Any {
        cleanupExpiredPendingChanges()

        switch action {
        case "get_status":
            return try statusJSON()
        case "get_system_load":
            return try systemLoadJSON()
        case "list_options":
            return try optionsJSON()
        case "prepare_setting_change":
            return try prepareSettingChange(params: params)
        case "confirm_setting_change":
            return try await confirmSettingChange(params: params)
        case "cancel_setting_change":
            return try cancelSettingChange(params: params)
        default:
            throw ControlFailure(code: "unknown_action", message: "Unknown control action: \(action)")
        }
    }

    private func responseData(id: Any, ok: Bool, data: Any?, error: Any?) -> Data {
        var object: [String: Any] = [
            "id": id,
            "ok": ok
        ]
        object["data"] = data ?? NSNull()
        object["error"] = error ?? NSNull()

        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            var fallback = Data(#"{"id":null,"ok":false,"data":null,"error":{"code":"serialization_failed","message":"Could not encode response."}}"#.utf8)
            fallback.append(10)
            return fallback
        }

        var response = data
        response.append(10)
        return response
    }

    private func errorJSON(code: String, message: String) -> [String: Any] {
        [
            "code": code,
            "message": message
        ]
    }

    @MainActor
    private func statusJSON() throws -> [String: Any] {
        guard let appState else {
            throw ControlFailure(code: "app_state_unavailable", message: "App state is not available.")
        }

        let readiness = AppState.lowBatteryNotificationReadiness()
        return [
            "app": [
                "name": "turnintoserver",
                "version": appVersion()
            ],
            "state": [
                "server_mode_requested": appState.serverModeRequested,
                "server_mode_active": appState.serverModeActive,
                "server_mode_status": appState.statusSummaryDisplay,
                "is_command_running": appState.isCommandRunning,
                "last_command_status": appState.lastCommandStatus,
                "power_source": appState.powerSource.rawValue,
                "lid_state": appState.lidState.rawValue,
                "allow_battery_server_mode": appState.allowBatteryServerMode,
                "timed_server_mode": timedServerModeJSON(appState),
                "low_battery_notifications": lowBatteryJSON(appState, readiness: readiness),
                "hot_keys": hotKeysJSON(appState),
                "launch_at_login": launchAtLoginJSON(appState)
            ],
            "control": [
                "socket_path": socketPath,
                "setting_changes_require_confirmation": true,
                "pending_confirmation_count": pendingSettingChanges.count
            ]
        ]
    }

    @MainActor
    private func systemLoadJSON() throws -> [String: Any] {
        guard let appState else {
            throw ControlFailure(code: "app_state_unavailable", message: "App state is not available.")
        }

        return [
            "system_pressure": systemPressureJSON(appState.systemPressure),
            "top_apps": appState.topMemoryApps.map { app in
                [
                    "id": app.id,
                    "name": app.name,
                    "resident_bytes": app.residentBytes,
                    "memory_display": app.memoryDisplay,
                    "percent_of_physical_memory": app.percentOfPhysicalMemory,
                    "cpu_percent": app.cpuPercent,
                    "cpu_display": app.percentDisplay
                ] as [String: Any]
            }
        ]
    }

    @MainActor
    private func optionsJSON() throws -> [[String: Any]] {
        guard let appState else {
            throw ControlFailure(code: "app_state_unavailable", message: "App state is not available.")
        }

        let readiness = AppState.lowBatteryNotificationReadiness()
        return [
            optionJSON(
                name: "server_mode",
                title: "Server Mode",
                valueType: "boolean",
                currentValue: appState.serverModeRequested || appState.serverModeActive,
                canSet: !appState.isCommandRunning,
                impact: "启动或关闭 Server Mode。关闭时仍会保留合盖无外接显示器的安全确认。"
            ),
            optionJSON(
                name: "allow_battery_server_mode",
                title: AppText.allowBatteryServerMode,
                valueType: "boolean",
                currentValue: appState.allowBatteryServerMode,
                canSet: !appState.isCommandRunning,
                impact: "允许或限制电池供电时继续运行 Server Mode。"
            ),
            optionJSON(
                name: "timed_server_mode_duration_minutes",
                title: AppText.timedServerMode,
                valueType: "integer_or_null",
                currentValue: appState.timedServerModeSelectedDurationMinutes ?? NSNull(),
                canSet: !appState.isCommandRunning,
                impact: "设置具体分钟数会启动定时 Server Mode；设置为 null 会清除当前定时。"
            ),
            optionJSON(
                name: "timed_server_mode_duration_options",
                title: AppText.timedServerModeSettingsTitle,
                valueType: "integer_array",
                currentValue: appState.timedServerModeDurationOptions,
                canSet: true,
                impact: "替换菜单中可选择的定时启动时长，范围为 1 到 10080 分钟。"
            ),
            optionJSON(
                name: "timed_server_mode_prevent_display_sleep",
                title: AppText.preventTimedServerModeDisplaySleep,
                valueType: "boolean",
                currentValue: appState.timedServerModePreventDisplaySleep,
                canSet: appState.canToggleTimedServerModePreventDisplaySleep,
                impact: "仅在当前存在定时倒计时时可切换，用于定时 Server Mode 期间阻止屏幕睡眠。"
            ),
            optionJSON(
                name: "low_battery_notifications",
                title: AppText.lowBatteryNotifications,
                valueType: "boolean",
                currentValue: appState.lowBatteryNotificationsEnabled,
                canSet: !appState.isCommandRunning && (!appState.lowBatteryNotificationsEnabled || readiness.canEnable),
                impact: "开启前至少需要一个通知通道已测试通过。"
            ),
            optionJSON(
                name: "low_battery_imessage_recipient",
                title: AppText.iMessageChannelTitle,
                valueType: "string",
                currentValue: maskedDefaultString(forKey: AppDefaultsKey.iMessageRecipientAddress),
                canSet: true,
                impact: "修改 iMessage 收件地址后，该通道需要重新测试。"
            ),
            optionJSON(
                name: "low_battery_bark_endpoint",
                title: AppText.barkChannelTitle,
                valueType: "string",
                currentValue: maskedDefaultString(forKey: AppDefaultsKey.barkPushEndpoint),
                canSet: true,
                impact: "修改 Bark 推送地址后，该通道需要重新测试。"
            ),
            optionJSON(
                name: "hot_keys_enabled",
                title: AppText.enableShortcuts,
                valueType: "boolean",
                currentValue: appState.hotKeysEnabled,
                canSet: true,
                impact: "启用或停用全局快捷键，不清除已录制的组合键。"
            ),
            optionJSON(
                name: "server_mode_hot_key",
                title: AppText.serverModeShortcutLabel,
                valueType: "hot_key_or_null",
                currentValue: hotKeyJSON(serverModeShortcut()),
                canSet: true,
                impact: "设置 Server Mode 快捷键；设置为 null 会清空该快捷键。"
            ),
            optionJSON(
                name: "battery_mode_hot_key",
                title: AppText.batteryModeShortcutLabel,
                valueType: "hot_key_or_null",
                currentValue: hotKeyJSON(batteryModeShortcut()),
                canSet: true,
                impact: "设置电池模式快捷键；设置为 null 会清空该快捷键。"
            ),
            optionJSON(
                name: "reset_hot_keys_to_defaults",
                title: AppText.resetShortcuts,
                valueType: "boolean",
                currentValue: false,
                canSet: true,
                impact: "恢复两个快捷键到默认组合。"
            ),
            optionJSON(
                name: "launch_at_login",
                title: AppText.launchAtLogin,
                valueType: "boolean",
                currentValue: appState.launchAtLoginEnabled,
                canSet: appState.launchAtLoginSupported && !appState.isLaunchAtLoginChanging,
                impact: "设置是否开机自动启动。macOS 13 以下不支持。"
            )
        ]
    }

    @MainActor
    private func prepareSettingChange(params: [String: Any]) throws -> [String: Any] {
        guard let option = params["option"] as? String else {
            throw ControlFailure(code: "missing_option", message: "Setting option is required.")
        }

        let rawValue = params["value"] ?? NSNull()
        let prepared = try prepareSetting(option: option, rawValue: rawValue)
        let id = UUID().uuidString
        let token = UUID().uuidString
        let now = Date()
        let expiresAt = now.addingTimeInterval(120)
        let pending = PendingSettingChange(
            id: id,
            token: token,
            option: prepared.option,
            title: prepared.title,
            value: prepared.value,
            currentValueForResponse: prepared.currentValueForResponse,
            requestedValueForResponse: prepared.requestedValueForResponse,
            impact: prepared.impact,
            stateSignature: stateSignature(),
            createdAt: now,
            expiresAt: expiresAt
        )
        pendingSettingChanges[id] = pending

        return [
            "confirmation_id": id,
            "confirmation_token": token,
            "expires_at": formatDate(expiresAt),
            "option": prepared.option,
            "title": prepared.title,
            "current_value": prepared.currentValueForResponse,
            "requested_value": prepared.requestedValueForResponse,
            "impact": prepared.impact,
            "next_step": "调用 turnintoserver_confirm_setting_change，并传入 confirmation_id 与 confirmation_token。"
        ]
    }

    @MainActor
    private func confirmSettingChange(params: [String: Any]) async throws -> [String: Any] {
        guard let confirmationID = params["confirmation_id"] as? String else {
            throw ControlFailure(code: "missing_confirmation_id", message: "confirmation_id is required.")
        }
        guard let confirmationToken = params["confirmation_token"] as? String else {
            throw ControlFailure(code: "missing_confirmation_token", message: "confirmation_token is required.")
        }
        guard let pending = pendingSettingChanges[confirmationID] else {
            throw ControlFailure(code: "confirmation_not_found", message: "No pending setting change matches that confirmation_id.")
        }
        guard pending.token == confirmationToken else {
            throw ControlFailure(code: "confirmation_token_mismatch", message: "confirmation_token does not match.")
        }
        guard pending.expiresAt > Date() else {
            pendingSettingChanges.removeValue(forKey: confirmationID)
            throw ControlFailure(code: "confirmation_expired", message: "The pending setting change has expired.")
        }
        guard pending.stateSignature == stateSignature() else {
            pendingSettingChanges.removeValue(forKey: confirmationID)
            throw ControlFailure(code: "state_changed", message: "App state changed after prepare_setting_change. Prepare the setting change again.")
        }

        pendingSettingChanges.removeValue(forKey: confirmationID)
        try await apply(pending)

        return [
            "applied": true,
            "option": pending.option,
            "title": pending.title,
            "requested_value": pending.requestedValueForResponse,
            "state": try statusJSON()
        ]
    }

    @MainActor
    private func cancelSettingChange(params: [String: Any]) throws -> [String: Any] {
        guard let confirmationID = params["confirmation_id"] as? String else {
            throw ControlFailure(code: "missing_confirmation_id", message: "confirmation_id is required.")
        }

        let removed = pendingSettingChanges.removeValue(forKey: confirmationID) != nil
        return [
            "cancelled": removed,
            "confirmation_id": confirmationID
        ]
    }

    @MainActor
    private func prepareSetting(option: String, rawValue: Any) throws -> PreparedSettingChange {
        guard let appState else {
            throw ControlFailure(code: "app_state_unavailable", message: "App state is not available.")
        }

        switch option {
        case "server_mode":
            let value = try boolValue(rawValue, option: option)
            return PreparedSettingChange(
                option: option,
                title: "Server Mode",
                value: .bool(value),
                currentValueForResponse: appState.serverModeRequested || appState.serverModeActive,
                requestedValueForResponse: value,
                impact: value
                    ? "将请求启动 Server Mode，并按当前电源策略执行。"
                    : "将请求关闭 Server Mode；如当前合盖且无外接显示器，app 仍会显示安全确认。"
            )
        case "allow_battery_server_mode":
            let value = try boolValue(rawValue, option: option)
            return PreparedSettingChange(
                option: option,
                title: AppText.allowBatteryServerMode,
                value: .bool(value),
                currentValueForResponse: appState.allowBatteryServerMode,
                requestedValueForResponse: value,
                impact: value
                    ? "Server Mode 将被允许在电池供电时继续运行。"
                    : "切到电池供电时 Server Mode 将按现有保护逻辑暂停。"
            )
        case "timed_server_mode_duration_minutes":
            if isNull(rawValue) {
                return PreparedSettingChange(
                    option: option,
                    title: AppText.timedServerMode,
                    value: .clearTimedServerMode,
                    currentValueForResponse: appState.timedServerModeSelectedDurationMinutes ?? NSNull(),
                    requestedValueForResponse: NSNull(),
                    impact: "将清除当前定时限制，但不会关闭正在运行的 Server Mode。"
                )
            }

            let minutes = try intValue(rawValue, option: option)
            guard let normalized = AppState.normalizedTimedServerModeDuration(minutes) else {
                throw ControlFailure(code: "invalid_value", message: "timed_server_mode_duration_minutes must be from 1 to 10080.")
            }
            return PreparedSettingChange(
                option: option,
                title: AppText.timedServerMode,
                value: .int(normalized),
                currentValueForResponse: appState.timedServerModeSelectedDurationMinutes ?? NSNull(),
                requestedValueForResponse: normalized,
                impact: "将按 \(normalized) 分钟重新开始定时 Server Mode。"
            )
        case "timed_server_mode_duration_options":
            let durations = try intArrayValue(rawValue, option: option)
            let sanitized = AppState.sanitizedTimedServerModeDurationOptions(durations)
            guard durations.allSatisfy({ AppState.normalizedTimedServerModeDuration($0) != nil }) else {
                throw ControlFailure(code: "invalid_value", message: "Every duration must be from 1 to 10080 minutes.")
            }
            return PreparedSettingChange(
                option: option,
                title: AppText.timedServerModeSettingsTitle,
                value: .intArray(sanitized),
                currentValueForResponse: appState.timedServerModeDurationOptions,
                requestedValueForResponse: sanitized,
                impact: "将替换定时启动菜单的可选时长。"
            )
        case "timed_server_mode_prevent_display_sleep":
            guard appState.canToggleTimedServerModePreventDisplaySleep else {
                throw ControlFailure(code: "option_unavailable", message: "This option can only be changed while a timed Server Mode countdown exists.")
            }
            let value = try boolValue(rawValue, option: option)
            return PreparedSettingChange(
                option: option,
                title: AppText.preventTimedServerModeDisplaySleep,
                value: .bool(value),
                currentValueForResponse: appState.timedServerModePreventDisplaySleep,
                requestedValueForResponse: value,
                impact: value
                    ? "定时 Server Mode 期间会额外阻止屏幕睡眠。"
                    : "定时 Server Mode 期间不再额外阻止屏幕睡眠。"
            )
        case "low_battery_notifications":
            let value = try boolValue(rawValue, option: option)
            if value && !AppState.canEnableLowBatteryNotifications() {
                throw ControlFailure(code: "option_unavailable", message: AppText.lowBatteryNotificationsRequireTest)
            }
            return PreparedSettingChange(
                option: option,
                title: AppText.lowBatteryNotifications,
                value: .bool(value),
                currentValueForResponse: appState.lowBatteryNotificationsEnabled,
                requestedValueForResponse: value,
                impact: value
                    ? "开启低电量通知。仅在 Server Mode、电池模式、电池供电同时成立时触发。"
                    : "关闭低电量通知并重置本轮阈值记录。"
            )
        case "low_battery_imessage_recipient":
            let value = try stringValue(rawValue, option: option)
            return PreparedSettingChange(
                option: option,
                title: AppText.iMessageChannelTitle,
                value: .string(value),
                currentValueForResponse: maskedDefaultString(forKey: AppDefaultsKey.iMessageRecipientAddress),
                requestedValueForResponse: mask(value),
                impact: "将更新 iMessage 收件地址；该通道需要重新测试后才能用于开启低电量通知。"
            )
        case "low_battery_bark_endpoint":
            let value = try stringValue(rawValue, option: option)
            return PreparedSettingChange(
                option: option,
                title: AppText.barkChannelTitle,
                value: .string(value),
                currentValueForResponse: maskedDefaultString(forKey: AppDefaultsKey.barkPushEndpoint),
                requestedValueForResponse: mask(value),
                impact: "将更新 Bark 推送地址；该通道需要重新测试后才能用于开启低电量通知。"
            )
        case "hot_keys_enabled":
            let value = try boolValue(rawValue, option: option)
            return PreparedSettingChange(
                option: option,
                title: AppText.enableShortcuts,
                value: .bool(value),
                currentValueForResponse: appState.hotKeysEnabled,
                requestedValueForResponse: value,
                impact: value ? "将启用全局快捷键。" : "将停用全局快捷键，但保留当前组合。"
            )
        case "server_mode_hot_key":
            let value = try hotKeyValue(rawValue, option: option)
            return PreparedSettingChange(
                option: option,
                title: AppText.serverModeShortcutLabel,
                value: .hotKey(value),
                currentValueForResponse: hotKeyJSON(serverModeShortcut()),
                requestedValueForResponse: hotKeyJSON(value),
                impact: "将更新或清空 Server Mode 快捷键。"
            )
        case "battery_mode_hot_key":
            let value = try hotKeyValue(rawValue, option: option)
            return PreparedSettingChange(
                option: option,
                title: AppText.batteryModeShortcutLabel,
                value: .hotKey(value),
                currentValueForResponse: hotKeyJSON(batteryModeShortcut()),
                requestedValueForResponse: hotKeyJSON(value),
                impact: "将更新或清空电池模式快捷键。"
            )
        case "reset_hot_keys_to_defaults":
            let value = try boolValue(rawValue, option: option)
            guard value else {
                throw ControlFailure(code: "invalid_value", message: "reset_hot_keys_to_defaults only accepts true.")
            }
            return PreparedSettingChange(
                option: option,
                title: AppText.resetShortcuts,
                value: .resetHotKeys,
                currentValueForResponse: hotKeysJSON(appState),
                requestedValueForResponse: true,
                impact: "将恢复两个全局快捷键到默认组合。"
            )
        case "launch_at_login":
            guard appState.launchAtLoginSupported else {
                throw ControlFailure(code: "option_unavailable", message: AppText.launchAtLoginUnsupported)
            }
            guard !appState.isLaunchAtLoginChanging else {
                throw ControlFailure(code: "command_running", message: "Open at Login status is changing.")
            }
            let value = try boolValue(rawValue, option: option)
            return PreparedSettingChange(
                option: option,
                title: AppText.launchAtLogin,
                value: .bool(value),
                currentValueForResponse: appState.launchAtLoginEnabled,
                requestedValueForResponse: value,
                impact: value ? "将注册为开机自动启动。" : "将取消开机自动启动。"
            )
        default:
            throw ControlFailure(code: "unknown_option", message: "Unknown setting option: \(option)")
        }
    }

    @MainActor
    private func apply(_ pending: PendingSettingChange) async throws {
        guard let appState else {
            throw ControlFailure(code: "app_state_unavailable", message: "App state is not available.")
        }

        switch (pending.option, pending.value) {
        case ("server_mode", .bool(let value)):
            await appState.setServerModeEnabled(value)
        case ("allow_battery_server_mode", .bool(let value)):
            appState.setAllowBatteryServerMode(value)
        case ("timed_server_mode_duration_minutes", .int(let value)):
            await appState.startTimedServerMode(durationMinutes: value)
        case ("timed_server_mode_duration_minutes", .clearTimedServerMode):
            appState.clearTimedServerModeTimer()
        case ("timed_server_mode_duration_options", .intArray(let values)):
            appState.setTimedServerModeDurationOptions(values)
        case ("timed_server_mode_prevent_display_sleep", .bool(let value)):
            appState.setTimedServerModePreventDisplaySleep(value)
        case ("low_battery_notifications", .bool(let value)):
            appState.setLowBatteryNotificationsEnabled(value)
        case ("low_battery_imessage_recipient", .string(let value)):
            appState.setLowBatteryIMessageRecipientAddress(value)
        case ("low_battery_bark_endpoint", .string(let value)):
            appState.setLowBatteryBarkPushEndpoint(value)
        case ("hot_keys_enabled", .bool(let value)):
            appState.setHotKeysEnabled(value)
        case ("server_mode_hot_key", .hotKey(let value)):
            saveHotKey(
                value,
                defaultsKey: AppDefaultsKey.serverModeHotKey,
                disabledDefaultsKey: AppDefaultsKey.serverModeHotKeyDisabled
            )
        case ("battery_mode_hot_key", .hotKey(let value)):
            saveHotKey(
                value,
                defaultsKey: AppDefaultsKey.batteryModeHotKey,
                disabledDefaultsKey: AppDefaultsKey.batteryModeHotKeyDisabled
            )
        case ("reset_hot_keys_to_defaults", .resetHotKeys):
            HotKeyShortcut.reset()
        case ("launch_at_login", .bool(let value)):
            appState.setLaunchAtLoginEnabled(value)
        default:
            throw ControlFailure(code: "invalid_pending_change", message: "Pending setting change is invalid.")
        }
    }

    private func optionJSON(
        name: String,
        title: String,
        valueType: String,
        currentValue: Any,
        canSet: Bool,
        impact: String
    ) -> [String: Any] {
        [
            "name": name,
            "title": title,
            "value_type": valueType,
            "current_value": currentValue,
            "can_set": canSet,
            "requires_confirmation": true,
            "impact": impact
        ]
    }

    @MainActor
    private func timedServerModeJSON(_ appState: AppState) -> [String: Any] {
        [
            "has_limit": appState.hasTimedServerModeLimit,
            "end_date": appState.timedServerModeEndDate.map(formatDate) ?? NSNull(),
            "selected_duration_minutes": appState.timedServerModeSelectedDurationMinutes ?? NSNull(),
            "remaining_display": appState.timedServerModeRemainingDisplay ?? NSNull(),
            "duration_options": appState.timedServerModeDurationOptions,
            "prevent_display_sleep": appState.timedServerModePreventDisplaySleep,
            "can_toggle_prevent_display_sleep": appState.canToggleTimedServerModePreventDisplaySleep
        ]
    }

    @MainActor
    private func lowBatteryJSON(
        _ appState: AppState,
        readiness: LowBatteryNotificationReadiness
    ) -> [String: Any] {
        [
            "enabled": appState.lowBatteryNotificationsEnabled,
            "can_enable": readiness.canEnable,
            "iMessage_configured": readiness.iMessageConfigured,
            "iMessage_verified": readiness.iMessageVerified,
            "iMessage_recipient": maskedDefaultString(forKey: AppDefaultsKey.iMessageRecipientAddress),
            "bark_configured": readiness.barkConfigured,
            "bark_verified": readiness.barkVerified,
            "bark_endpoint": maskedDefaultString(forKey: AppDefaultsKey.barkPushEndpoint)
        ]
    }

    @MainActor
    private func hotKeysJSON(_ appState: AppState) -> [String: Any] {
        [
            "enabled": appState.hotKeysEnabled,
            "server_mode": hotKeyJSON(serverModeShortcut()),
            "battery_mode": hotKeyJSON(batteryModeShortcut())
        ]
    }

    @MainActor
    private func launchAtLoginJSON(_ appState: AppState) -> [String: Any] {
        [
            "enabled": appState.launchAtLoginEnabled,
            "supported": appState.launchAtLoginSupported,
            "is_changing": appState.isLaunchAtLoginChanging
        ]
    }

    private func systemPressureJSON(_ snapshot: SystemPressureSnapshot?) -> Any {
        guard let snapshot else {
            return NSNull()
        }

        return [
            "memory_used_bytes": snapshot.memoryUsedBytes,
            "memory_display": snapshot.memoryDisplay,
            "memory_percent": snapshot.memoryPercent,
            "memory_percent_display": snapshot.memoryPercentDisplay,
            "cpu_percent": snapshot.cpuPercent,
            "cpu_display": snapshot.cpuPercentDisplay
        ] as [String: Any]
    }

    private func hotKeyJSON(_ shortcut: HotKeyShortcut?) -> Any {
        guard let shortcut else {
            return NSNull()
        }

        return [
            "key_code": shortcut.keyCode,
            "modifier_flags": shortcut.modifierFlags,
            "key_display": shortcut.keyDisplay,
            "display": shortcut.menuDisplayString
        ] as [String: Any]
    }

    private func saveHotKey(_ shortcut: HotKeyShortcut?, defaultsKey: String, disabledDefaultsKey: String) {
        if let shortcut {
            shortcut.save(defaultsKey: defaultsKey, disabledDefaultsKey: disabledDefaultsKey)
        } else {
            HotKeyShortcut.clear(defaultsKey: defaultsKey, disabledDefaultsKey: disabledDefaultsKey)
        }
    }

    private func serverModeShortcut() -> HotKeyShortcut? {
        HotKeyShortcut.loadOptional(
            defaultsKey: AppDefaultsKey.serverModeHotKey,
            disabledDefaultsKey: AppDefaultsKey.serverModeHotKeyDisabled,
            default: .defaultServerMode
        )
    }

    private func batteryModeShortcut() -> HotKeyShortcut? {
        HotKeyShortcut.loadOptional(
            defaultsKey: AppDefaultsKey.batteryModeHotKey,
            disabledDefaultsKey: AppDefaultsKey.batteryModeHotKeyDisabled,
            default: .defaultBatteryMode
        )
    }

    private func boolValue(_ value: Any, option: String) throws -> Bool {
        guard let bool = value as? Bool else {
            throw ControlFailure(code: "invalid_value", message: "\(option) must be a boolean.")
        }
        return bool
    }

    private func intValue(_ value: Any, option: String) throws -> Int {
        guard let number = value as? NSNumber,
              !isBoolNumber(number),
              number.doubleValue.isFinite,
              number.doubleValue.rounded() == number.doubleValue else {
            throw ControlFailure(code: "invalid_value", message: "\(option) must be an integer.")
        }
        return number.intValue
    }

    private func intArrayValue(_ value: Any, option: String) throws -> [Int] {
        guard let array = value as? [Any] else {
            throw ControlFailure(code: "invalid_value", message: "\(option) must be an array of integers.")
        }
        return try array.map { try intValue($0, option: option) }
    }

    private func stringValue(_ value: Any, option: String) throws -> String {
        guard let string = value as? String else {
            throw ControlFailure(code: "invalid_value", message: "\(option) must be a string.")
        }
        return string
    }

    private func hotKeyValue(_ value: Any, option: String) throws -> HotKeyShortcut? {
        if isNull(value) {
            return nil
        }

        guard let object = value as? [String: Any] else {
            throw ControlFailure(code: "invalid_value", message: "\(option) must be null or a hot key object.")
        }
        guard let keyCode = uint32Value(object["key_code"], field: "key_code"),
              let modifierFlags = uint32Value(object["modifier_flags"], field: "modifier_flags"),
              let keyDisplay = object["key_display"] as? String,
              !keyDisplay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ControlFailure(
                code: "invalid_value",
                message: "\(option) hot key object requires key_code, modifier_flags, and key_display."
            )
        }
        guard modifierFlags != 0 else {
            throw ControlFailure(code: "invalid_value", message: "\(option) modifier_flags must not be zero.")
        }

        return HotKeyShortcut(
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            keyDisplay: keyDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func uint32Value(_ value: Any?, field: String) -> UInt32? {
        guard let number = value as? NSNumber,
              !isBoolNumber(number),
              number.doubleValue.isFinite,
              number.doubleValue.rounded() == number.doubleValue,
              number.uint64Value <= UInt64(UInt32.max) else {
            return nil
        }
        return number.uint32Value
    }

    private func isBoolNumber(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private func isNull(_ value: Any) -> Bool {
        value is NSNull
    }

    private func cleanupExpiredPendingChanges() {
        let now = Date()
        pendingSettingChanges = pendingSettingChanges.filter { _, pending in
            pending.expiresAt > now
        }
    }

    @MainActor
    private func stateSignature() -> String {
        guard let appState else {
            return "missing"
        }

        let defaults = UserDefaults.standard
        let values: [String] = [
            "\(appState.serverModeRequested)",
            "\(appState.serverModeActive)",
            "\(appState.isCommandRunning)",
            appState.powerSource.rawValue,
            appState.lidState.rawValue,
            "\(appState.allowBatteryServerMode)",
            "\(appState.lowBatteryNotificationsEnabled)",
            "\(appState.hotKeysEnabled)",
            "\(appState.launchAtLoginEnabled)",
            "\(appState.timedServerModeEndDate?.timeIntervalSince1970 ?? 0)",
            "\(appState.timedServerModeSelectedDurationMinutes ?? -1)",
            appState.timedServerModeDurationOptions.map(String.init).joined(separator: ","),
            "\(appState.timedServerModePreventDisplaySleep)",
            defaults.string(forKey: AppDefaultsKey.iMessageRecipientAddress) ?? "",
            defaults.string(forKey: AppDefaultsKey.barkPushEndpoint) ?? "",
            hotKeySignature(serverModeShortcut()),
            hotKeySignature(batteryModeShortcut())
        ]
        return values.joined(separator: "|")
    }

    private func hotKeySignature(_ shortcut: HotKeyShortcut?) -> String {
        guard let shortcut else {
            return "nil"
        }
        return "\(shortcut.keyCode):\(shortcut.modifierFlags):\(shortcut.keyDisplay)"
    }

    private func maskedDefaultString(forKey key: String) -> String {
        mask(UserDefaults.standard.string(forKey: key) ?? "")
    }

    private func mask(_ value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return ""
        }

        guard trimmedValue.count > 6 else {
            return String(repeating: "*", count: trimmedValue.count)
        }

        let prefix = trimmedValue.prefix(2)
        let suffix = trimmedValue.suffix(2)
        return "\(prefix)...\(suffix)"
    }

    private func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? AppText.unknownVersion
    }

    private func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
