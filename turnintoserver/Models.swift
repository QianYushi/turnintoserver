import Foundation

enum AppText {
    static var notStarted: String {
        localized(chinese: "未启动", english: "Not Running")
    }

    static var keepsRunningWithLidClosed: String {
        localized(chinese: "合盖也会保持运行", english: "Keeps running with lid closed")
    }

    static var connectPowerToKeepRunningWithLidClosed: String {
        localized(
            chinese: "接入电源后，合盖也会保持运行",
            english: "Connect power to keep running with lid closed"
        )
    }

    static var startServerMode: String {
        localized(chinese: "启动 Server 模式", english: "Start Server Mode")
    }

    static var stopServerMode: String {
        localized(chinese: "关闭 Server 模式", english: "Turn Off Server Mode")
    }

    static var allowBatteryServerMode: String {
        localized(chinese: "电池也允许 Server 模式", english: "Allow Server Mode on Battery")
    }

    static var launchAtLogin: String {
        localized(chinese: "开机自动启动", english: "Open at Login")
    }

    static var quit: String {
        localized(chinese: "退出", english: "Quit")
    }

    static var serverModeOnBatteryAllowed: String {
        localized(chinese: "Server 模式已开启 - 允许电池", english: "Server Mode On - Battery Allowed")
    }

    static var serverModeOnPowerOnly: String {
        localized(chinese: "Server 模式已开启 - 仅接电源", english: "Server Mode On - Power Adapter Only")
    }

    static var waitingForPowerAdapter: String {
        localized(chinese: "等待接入电源", english: "Waiting for Power Adapter")
    }

    static var launchAtLoginOn: String {
        localized(chinese: "开机启动已开启", english: "Open at Login is on")
    }

    static var launchAtLoginOff: String {
        localized(chinese: "开机启动已关闭", english: "Open at Login is off")
    }

    static var launchAtLoginRequiresApproval: String {
        localized(chinese: "需在系统设置中允许开机启动", english: "Allow Open at Login in System Settings")
    }

    static var launchAtLoginAppNotFound: String {
        localized(chinese: "未找到可注册的 App", english: "No app found to register")
    }

    static var launchAtLoginUnknown: String {
        localized(chinese: "开机启动状态未知", english: "Open at Login status unknown")
    }

    static func localized(chinese: String, english: String) -> String {
        isChinesePreferred ? chinese : english
    }

    private static var isChinesePreferred: Bool {
        let identifier = Locale.preferredLanguages.first ?? Locale.current.identifier
        return identifier.lowercased().hasPrefix("zh")
    }
}

enum PowerSource: String, Codable, Equatable {
    case acPower = "AC Power"
    case batteryPower = "Battery Power"
    case unknown = "Unknown"

    init(pmsetBatteryOutput output: String) {
        if output.contains("Now drawing from 'AC Power'") {
            self = .acPower
        } else if output.contains("Now drawing from 'Battery Power'") {
            self = .batteryPower
        } else {
            self = .unknown
        }
    }

    init(ioKitPowerSourceType type: String) {
        self = PowerSource(rawValue: type) ?? .unknown
    }
}

enum LidState: String, Codable, Equatable {
    case open = "Open"
    case closed = "Closed"
    case unknown = "Unknown"

    init(ioregOutput output: String) {
        if output.contains(#""AppleClamshellState" = Yes"#) {
            self = .closed
        } else if output.contains(#""AppleClamshellState" = No"#) {
            self = .open
        } else {
            self = .unknown
        }
    }
}

enum MenuBarIconStyle: Equatable {
    case idle
    case serverModePowerOnly
    case serverModeBatteryAllowed
}

struct PowerSettingsSnapshot: Codable, Equatable {
    var sleep: Int?
    var displaysleep: Int?
    var disablesleep: Int?

    var hasAnyValue: Bool {
        sleep != nil || displaysleep != nil || disablesleep != nil
    }
}

struct ShellResult: Equatable {
    var stdout: String
    var stderr: String
    var exitCode: Int32

    var combinedOutput: String {
        [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum ShellRunnerError: LocalizedError {
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        }
    }
}

enum PowerCommandResult: Equatable {
    case success(String)
    case userCancelled
    case failure(String)
}

enum PowerManagerError: LocalizedError {
    case unsupportedUserName

    var errorDescription: String? {
        switch self {
        case .unsupportedUserName:
            return "当前用户名包含 sudoers 不支持的字符"
        }
    }
}
