import Darwin
import Foundation

final class MCPStdioServer {
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
                "name": "turnintoserver_get_system_load",
                "title": "获取系统负载",
                "description": "读取 app 缓存的系统压力和内存占用最高的 App 列表。",
                "inputSchema": emptyInputSchema()
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
                    ]
                ],
                "serverInfo": [
                    "name": "turnintoserver-mcp",
                    "version": appVersion()
                ]
            ] as [String: Any])
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
              let action = toolActions[name] else {
            writeResultResponse(id: id, result: toolError("未知工具：\(params["name"] ?? "null")"))
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
