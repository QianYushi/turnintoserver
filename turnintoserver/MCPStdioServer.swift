import Darwin
import Foundation

final class MCPStdioServer {
    static let agentGuideVersion = "2026-05-29.2"
    private static let agentGuidePromptName = "turnintoserver_agent_guide"
    private static let agentGuideText = """
    turnintoserver MCP agent guide
    Version: 2026-05-29.2

    Treat this text as the operating guide for the local turnintoserver MCP. If you are installing or upgrading this MCP for a host agent, store or refresh these rules in that agent's local instructions, skill, memory, or equivalent system guidance when the host supports that.

    Core rules:
    - For questions about turnintoserver itself, Server Mode, power/lid state, launch at login, shortcuts, timed Server Mode, low battery alerts, system pressure, app memory usage, or 24-hour memory/CPU peaks, call this MCP first. Do not guess, and do not use ps/top/defaults as the first source when a turnintoserver tool can answer.
    - If a user asks whether the Mac will stay awake, whether closing the lid is safe, whether an update worked, what the current app version is, or what setting is enabled, call turnintoserver_get_app_state first.
    - If a user asks about load, "卡不卡", CPU, memory, pressure, top apps, or a named app's peak usage, call turnintoserver_get_system_load or turnintoserver_get_memory_history before answering.
    - If the host agent tends not to call MCP automatically, treat this guide as an explicit routing policy: any user request matching a read-only or settings case below must start with the matching turnintoserver MCP tool.
    - If a tool result is missing, old, unavailable, or limited to the current app runtime, say that clearly instead of inventing an answer.
    - This MCP has no npm, Node.js, or external dependency requirement. The stdio command is the installed app executable with args ["--mcp-server"].

    Installation and upgrade:
    - Install or update the MCP command to the currently running turnintoserver.app executable: <running app>/Contents/MacOS/turnintoserver with args ["--mcp-server"].
    - Never hard-code a user's home directory. Use the currently running app path when the host can discover it.
    - Treat install and upgrade the same way: overwrite the existing turnintoserver MCP command and args if they differ, but keep unrelated MCP servers and unrelated host-agent settings.
    - If multiple turnintoserver.app copies exist, prefer the currently running app. If no copy is running, prefer the app selected by the user or the normal installed app path.
    - After first install or any incremental upgrade, read this guide again. If the guide version changed, replace the older stored instructions. If the host supports MCP prompts, read prompt turnintoserver_agent_guide; otherwise call turnintoserver_get_agent_guide.
    - Verify the connection with turnintoserver_get_app_state.
    - If verification fails, check that the app is running, that the command points to Contents/MacOS/turnintoserver inside the chosen app, and that args are exactly ["--mcp-server"]. Do not run npm install or download dependencies.

    Read-only questions:
    - Use turnintoserver_get_app_state for current app state: Server Mode requested/active, power source, lid state, timed Server Mode, low battery notification readiness, shortcut settings, launch at login, and guide version.
    - Use turnintoserver_get_system_load for current system pressure and the current memory top apps.
    - Use turnintoserver_get_memory_history for historical memory/CPU questions. For example, "过去24小时 Codex 峰值内存" means call turnintoserver_get_memory_history with {"app":"Codex"}. Report peak memory, peak timestamp, current memory, and that history is in-memory and limited to the current turnintoserver runtime, up to 24 hours.
    - If the user asks about "Codex", "Hermes", "Chrome", or another app by name, pass that name as the app query instead of requiring an exact bundle path.

    Settings and actions:
    - Use turnintoserver_list_options before changing settings so you know valid option names, current values, availability, value types, and impact.
    - All setting changes require two steps. First call turnintoserver_prepare_setting_change. Show or internally validate the returned impact. Then call turnintoserver_confirm_setting_change with confirmation_id and confirmation_token. Use turnintoserver_cancel_setting_change when the user changes their mind.
    - Do not bypass the two-step flow with shell commands or direct defaults writes.
    - If prepare_setting_change says an option is unavailable, report the reason and the next useful action.
    - If confirmation fails or expires, do not reuse old tokens. Run prepare_setting_change again and then confirm the new confirmation_id and confirmation_token.

    Common mappings:
    - "现在有没有开 Server Mode / 合盖会不会保持运行" -> turnintoserver_get_app_state.
    - "系统压力 / CPU / 内存 Top App" -> turnintoserver_get_system_load.
    - "过去24小时某 App 峰值内存/CPU" -> turnintoserver_get_memory_history.
    - "打开/关闭 Server Mode" -> list_options, prepare_setting_change option "server_mode", then confirm.
    - "电池也允许 Server Mode" -> option "allow_battery_server_mode".
    - "定时启动多久 / 清除定时" -> option "timed_server_mode_duration_minutes"; use null to clear.
    - "修改定时启动的可选时长" -> option "timed_server_mode_duration_options"; use an array of minutes.
    - "定时期间阻止屏幕睡眠" -> option "timed_server_mode_prevent_display_sleep"; only available during an active timed countdown.
    - "低电量通知" -> option "low_battery_notifications"; channel addresses may need testing in the app before enabling.
    - "iMessage 低电量通知收件人" -> option "low_battery_imessage_recipient".
    - "Bark 低电量通知地址" -> option "low_battery_bark_endpoint"; MCP output masks existing secrets.
    - "开机自动启动" -> option "launch_at_login".
    - "快捷键" -> options "hot_keys_enabled", "server_mode_hot_key", "battery_mode_hot_key", or "reset_hot_keys_to_defaults".

    Troubleshooting:
    - If turnintoserver_get_memory_history returns no matching app, retry with a shorter app name such as "Codex" instead of a full path, then fall back to turnintoserver_get_system_load for current top apps.
    - If historical data is shorter than requested, explain that turnintoserver stores history in memory for the current app runtime, up to 24 hours. After app restart or update, older samples are not available.
    - If the host agent already had an older turnintoserver MCP entry, update it in place instead of adding a duplicate entry.
    - If the host agent supports skills, memory, or local instruction files, store this guide there after install or upgrade so future user questions route to the MCP immediately.
    - If a setting is not listed by turnintoserver_list_options, do not invent a hidden option. Report that the current app version does not expose it.

    Privacy and wording:
    - Endpoint-like values such as Bark URLs are intentionally masked in MCP output. Do not ask the user to reveal secrets unless a setting change truly requires it.
    - Prefer concise answers grounded in tool output. Include concrete values and timestamps for measurements.
    """

    private struct StdioFailure: LocalizedError {
        let code: String
        let message: String

        var errorDescription: String? {
            message
        }
    }

    private let socketPath: String

    private var tools: [[String: Any]] {
        [
            [
                "name": "turnintoserver_get_app_state",
                "title": "获取应用状态",
                "description": "读取 turnintoserver 当前 Server Mode、电源、合盖、定时、低电量通知、快捷键和开机启动状态。",
                "inputSchema": emptyInputSchema()
            ],
            [
                "name": "turnintoserver_get_agent_guide",
                "title": "获取 agent 使用指南",
                "description": "读取内置的 turnintoserver MCP 使用规则。安装 MCP 后应先读取并遵循这份指南。",
                "inputSchema": emptyInputSchema()
            ],
            [
                "name": "turnintoserver_get_system_load",
                "title": "获取系统负载",
                "description": "读取 app 缓存的系统压力和内存占用最高的 App 列表。",
                "inputSchema": emptyInputSchema()
            ],
            [
                "name": "turnintoserver_get_memory_history",
                "title": "获取内存历史",
                "description": "读取系统压力或指定 App 在当前 turnintoserver 运行期内、最多过去 24 小时的内存和 CPU 峰值。",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "app": [
                            "type": "string",
                            "description": "可选。App 名称、bundle 路径或关键字，例如 Codex。省略时返回系统压力历史。"
                        ],
                        "include_points": [
                            "type": "boolean",
                            "description": "可选。是否返回历史采样点，默认 false。"
                        ],
                        "max_points": [
                            "type": "integer",
                            "description": "可选。返回采样点的最大数量，默认 120，最大 2000。"
                        ]
                    ],
                    "additionalProperties": false
                ] as [String: Any]
            ],
            [
                "name": "turnintoserver_list_options",
                "title": "列出可设置选项",
                "description": "列出 MCP 可修改的 turnintoserver 选项、当前值、参数类型、可用性和影响说明。",
                "inputSchema": emptyInputSchema()
            ],
            [
                "name": "turnintoserver_prepare_setting_change",
                "title": "预备修改设置",
                "description": "第一步：校验设置修改并生成确认单，不会真正执行修改。所有设置修改都必须先调用本工具。",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "option": [
                            "type": "string",
                            "description": "选项名称，来自 turnintoserver_list_options 的 name 字段。"
                        ],
                        "value": [
                            "description": "目标值。类型必须匹配该选项的 value_type。"
                        ]
                    ],
                    "required": ["option", "value"],
                    "additionalProperties": false
                ] as [String: Any]
            ],
            [
                "name": "turnintoserver_confirm_setting_change",
                "title": "确认修改设置",
                "description": "第二步：使用预备修改设置返回的 confirmation_id 和 confirmation_token 真正执行设置修改。",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "confirmation_id": [
                            "type": "string",
                            "description": "预备修改设置返回的 confirmation_id。"
                        ],
                        "confirmation_token": [
                            "type": "string",
                            "description": "预备修改设置返回的 confirmation_token。"
                        ]
                    ],
                    "required": ["confirmation_id", "confirmation_token"],
                    "additionalProperties": false
                ] as [String: Any]
            ],
            [
                "name": "turnintoserver_cancel_setting_change",
                "title": "取消待确认修改",
                "description": "取消尚未确认执行的设置修改。",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "confirmation_id": [
                            "type": "string",
                            "description": "预备修改设置返回的 confirmation_id。"
                        ]
                    ],
                    "required": ["confirmation_id"],
                    "additionalProperties": false
                ] as [String: Any]
            ]
        ]
    }

    private var toolActions: [String: String] {
        [
            "turnintoserver_get_app_state": "get_status",
            "turnintoserver_get_system_load": "get_system_load",
            "turnintoserver_get_memory_history": "get_memory_history",
            "turnintoserver_list_options": "list_options",
            "turnintoserver_prepare_setting_change": "prepare_setting_change",
            "turnintoserver_confirm_setting_change": "confirm_setting_change",
            "turnintoserver_cancel_setting_change": "cancel_setting_change"
        ]
    }

    init(socketPath: String = MCPStdioServer.defaultSocketPath()) {
        self.socketPath = ProcessInfo.processInfo.environment["TURNINTOSERVER_CONTROL_SOCKET"] ?? socketPath
    }

    func run() {
        while let line = readLine() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else {
                continue
            }

            guard let data = trimmedLine.data(using: .utf8) else {
                writeErrorResponse(id: NSNull(), code: -32700, message: "Parse error: input is not valid UTF-8.")
                continue
            }

            do {
                guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    writeErrorResponse(id: NSNull(), code: -32600, message: "Invalid Request: message must be a JSON object.")
                    continue
                }

                handle(message)
            } catch {
                writeErrorResponse(id: NSNull(), code: -32700, message: "Parse error: \(error.localizedDescription)")
            }
        }
    }

    private func handle(_ message: [String: Any]) {
        let id = message["id"] ?? NSNull()
        guard let method = message["method"] as? String else {
            if message["id"] != nil {
                writeErrorResponse(id: id, code: -32600, message: "Invalid Request: method is required.")
            }
            return
        }

        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            writeResultResponse(id: id, result: [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": [
                    "tools": [
                        "listChanged": false
                    ],
                    "prompts": [
                        "listChanged": false
                    ]
                ],
                "serverInfo": [
                    "name": "turnintoserver-mcp",
                    "version": appVersion()
                ]
            ] as [String: Any])
        case "prompts/list":
            writeResultResponse(id: id, result: [
                "prompts": [
                    [
                        "name": Self.agentGuidePromptName,
                        "title": "turnintoserver MCP 使用指南",
                        "description": "安装 turnintoserver MCP 后给 agent 读取的内置使用规则。",
                        "arguments": []
                    ] as [String: Any]
                ]
            ] as [String: Any])
        case "prompts/get":
            handlePromptGet(id: id, params: params)
        case "tools/list":
            writeResultResponse(id: id, result: ["tools": tools])
        case "tools/call":
            handleToolCall(id: id, params: params)
        default:
            if method.hasPrefix("notifications/") {
                return
            }
            if message["id"] != nil {
                writeErrorResponse(id: id, code: -32601, message: "Method not found: \(method)")
            }
        }
    }

    private func handleToolCall(id: Any, params: [String: Any]) {
        guard let name = params["name"] as? String,
              name == "turnintoserver_get_agent_guide" || toolActions[name] != nil else {
            writeResultResponse(id: id, result: toolError("未知工具：\(params["name"] ?? "null")"))
            return
        }

        if name == "turnintoserver_get_agent_guide" {
            writeResultResponse(id: id, result: [
                "content": [
                    [
                        "type": "text",
                        "text": Self.agentGuideText
                    ]
                ]
            ] as [String: Any])
            return
        }

        guard let action = toolActions[name] else {
            writeResultResponse(id: id, result: toolError("未知工具：\(name)"))
            return
        }

        let arguments = params["arguments"] as? [String: Any] ?? [:]

        do {
            let data = try controlRequest(action: action, params: arguments)
            writeResultResponse(id: id, result: toolResult(data))
        } catch let failure as StdioFailure {
            writeResultResponse(id: id, result: toolError("\(failure.code): \(failure.message)"))
        } catch {
            writeResultResponse(id: id, result: toolError(error.localizedDescription))
        }
    }

    private func handlePromptGet(id: Any, params: [String: Any]) {
        guard let name = params["name"] as? String else {
            writeErrorResponse(id: id, code: -32602, message: "Invalid params: prompt name is required.")
            return
        }

        guard name == Self.agentGuidePromptName else {
            writeErrorResponse(id: id, code: -32602, message: "Unknown prompt: \(name)")
            return
        }

        writeResultResponse(id: id, result: [
            "description": "turnintoserver MCP 使用指南",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        "type": "text",
                        "text": Self.agentGuideText
                    ]
                ]
            ]
        ] as [String: Any])
    }

    private func controlRequest(action: String, params: [String: Any]) throws -> Any {
        do {
            return try sendControlRequest(action: action, params: params)
        } catch {
            launchContainingAppIfPossible()
            waitForControlSocket()
            return try sendControlRequest(action: action, params: params)
        }
    }

    private func sendControlRequest(action: String, params: [String: Any]) throws -> Any {
        let fileDescriptor = try connectToControlSocket()
        defer {
            Darwin.close(fileDescriptor)
        }

        let request: [String: Any] = [
            "id": UUID().uuidString,
            "action": action,
            "params": params
        ]
        guard let requestData = try? JSONSerialization.data(withJSONObject: request) else {
            throw StdioFailure(code: "serialization_failed", message: "无法编码 turnintoserver 控制请求。")
        }

        var line = requestData
        line.append(10)
        try writeAll(line, to: fileDescriptor)

        let responseLine = try readLineData(from: fileDescriptor)
        guard let response = try JSONSerialization.jsonObject(with: responseLine) as? [String: Any] else {
            throw StdioFailure(code: "invalid_control_response", message: "turnintoserver 控制服务返回了无效 JSON。")
        }

        if response["ok"] as? Bool == true {
            return response["data"] ?? NSNull()
        }

        let errorInfo = response["error"] as? [String: Any]
        let code = errorInfo?["code"] as? String ?? "control_error"
        let message = errorInfo?["message"] as? String ?? "turnintoserver 控制服务返回错误。"
        throw StdioFailure(code: code, message: message)
    }

    private func connectToControlSocket() throws -> Int32 {
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw StdioFailure(code: "socket_failed", message: String(cString: strerror(errno)))
        }

        do {
            var timeout = timeval(tv_sec: 8, tv_usec: 0)
            _ = withUnsafePointer(to: &timeout) { pointer in
                setsockopt(
                    fileDescriptor,
                    SOL_SOCKET,
                    SO_RCVTIMEO,
                    pointer,
                    socklen_t(MemoryLayout<timeval>.size)
                )
            }
            _ = withUnsafePointer(to: &timeout) { pointer in
                setsockopt(
                    fileDescriptor,
                    SOL_SOCKET,
                    SO_SNDTIMEO,
                    pointer,
                    socklen_t(MemoryLayout<timeval>.size)
                )
            }

            var address = sockaddr_un()
            let pathBytes = Array(socketPath.utf8CString)
            let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
            guard pathBytes.count <= maxPathLength else {
                throw StdioFailure(code: "socket_path_too_long", message: "Control socket path is too long.")
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

            let connectResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    Darwin.connect(fileDescriptor, socketAddress, socklen_t(addressLength))
                }
            }
            guard connectResult == 0 else {
                throw StdioFailure(code: "control_connect_failed", message: String(cString: strerror(errno)))
            }

            return fileDescriptor
        } catch {
            Darwin.close(fileDescriptor)
            throw error
        }
    }

    private func writeAll(_ data: Data, to fileDescriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
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
                    throw StdioFailure(code: "control_write_failed", message: String(cString: strerror(errno)))
                }
            }
        }
    }

    private func readLineData(from fileDescriptor: Int32) throws -> Data {
        var data = Data()
        var byte: UInt8 = 0

        while true {
            let result = Darwin.read(fileDescriptor, &byte, 1)
            if result == 1 {
                if byte == 10 {
                    return data
                }
                data.append(byte)
            } else if result == 0 {
                if data.isEmpty {
                    throw StdioFailure(code: "control_closed", message: "turnintoserver 控制服务未返回响应。")
                }
                return data
            } else if errno != EINTR {
                let message = errno == EAGAIN
                    ? "连接 turnintoserver 控制服务超时。请确认 app 已启动。"
                    : String(cString: strerror(errno))
                throw StdioFailure(code: "control_read_failed", message: message)
            }
        }
    }

    private func launchContainingAppIfPossible() {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-gj", bundleURL.path]
        try? process.run()
        process.waitUntilExit()
    }

    private func waitForControlSocket() {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: socketPath) {
                Thread.sleep(forTimeInterval: 0.25)
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private func writeResultResponse(id: Any, result: Any) {
        writeJSON([
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ])
    }

    private func writeErrorResponse(id: Any, code: Int, message: String) {
        writeJSON([
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": code,
                "message": message
            ]
        ] as [String: Any])
    }

    private func writeJSON(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            FileHandle.standardOutput.write(Data(#"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error: response serialization failed."}}"#.utf8))
            FileHandle.standardOutput.write(Data([10]))
            return
        }

        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }

    private func toolResult(_ value: Any) -> [String: Any] {
        [
            "content": [
                [
                    "type": "text",
                    "text": prettyJSONString(value)
                ]
            ]
        ]
    }

    private func toolError(_ message: String) -> [String: Any] {
        [
            "isError": true,
            "content": [
                [
                    "type": "text",
                    "text": message
                ]
            ]
        ]
    }

    private func prettyJSONString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return text
    }

    private func emptyInputSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [String: Any](),
            "additionalProperties": false
        ]
    }

    private func appVersion() -> String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, buildVersion) {
        case let (short?, build?) where !short.isEmpty && !build.isEmpty:
            return "\(short) (\(build))"
        case let (short?, _) where !short.isEmpty:
            return short
        default:
            return "0.1.0"
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
}
