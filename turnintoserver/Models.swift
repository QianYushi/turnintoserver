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

    static func serverModeRuntime(totalMinutes: Int) -> String {
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if isChinesePreferred {
            var parts: [String] = []
            if days > 0 {
                parts.append("\(days)天")
            }
            if hours > 0 {
                parts.append("\(hours)小时")
            }
            parts.append("\(minutes)分钟")
            return "已经运行" + parts.joined()
        }

        var parts: [String] = []
        if days > 0 {
            parts.append("\(days)d")
        }
        if hours > 0 {
            parts.append("\(hours)h")
        }
        parts.append("\(minutes)m")
        return "Running for " + parts.joined(separator: " ")
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

    static var aboutApp: String {
        localized(chinese: "关于应用", english: "About")
    }

    static var quit: String {
        localized(chinese: "退出", english: "Quit")
    }

    static var cancel: String {
        localized(chinese: "取消", english: "Cancel")
    }

    static var stopServerModeConfirmationTitle: String {
        localized(chinese: "确认关闭 Server Mode？", english: "Turn off Server Mode?")
    }

    static var stopServerModeConfirmationMessage: String {
        localized(
            chinese: "当前检测到 MacBook 已合盖，并且没有外接显示器。关闭 Server Mode 后，这台 Mac 可能会进入睡眠，远程连接可能会断开。",
            english: "This MacBook appears to be closed with no external display connected. Turning off Server Mode may put this Mac to sleep and disconnect remote sessions."
        )
    }

    static var stopServerModeConfirmationContinue: String {
        localized(chinese: "继续关闭", english: "Turn Off")
    }

    static func currentVersion(_ version: String) -> String {
        localized(chinese: "当前版本：\(version)", english: "Current version: \(version)")
    }

    static func developer(_ name: String) -> String {
        localized(chinese: "开发者：\(name)", english: "Developer: \(name)")
    }

    static var githubPrefix: String {
        "GitHub:"
    }

    static var githubURLDisplay: String {
        "https://github.com/QianYushi/turnintoserver"
    }

    static var shortcutHintsTitle: String {
        localized(chinese: "快捷键", english: "Shortcuts")
    }

    static var serverModeShortcutHint: String {
        localized(chinese: "⌃⌥⌘O：切换 Server Mode", english: "⌃⌥⌘O: Toggle Server Mode")
    }

    static var batteryModeShortcutHint: String {
        localized(chinese: "⌃⌥⌘P：切换电池模式", english: "⌃⌥⌘P: Toggle Battery Mode")
    }

    static var checkForUpdates: String {
        localized(chinese: "检查更新", english: "Check for Updates")
    }

    static var updateIdle: String {
        localized(chinese: "可以检查 GitHub Release 里的最新版。", english: "Check the latest GitHub release.")
    }

    static var checkingForUpdates: String {
        localized(chinese: "正在检查更新…", english: "Checking for updates...")
    }

    static var alreadyUpToDate: String {
        localized(chinese: "当前已经是最新版本。", english: "You are already on the latest version.")
    }

    static func updateAvailable(_ version: String) -> String {
        localized(chinese: "发现新版本 \(version)，可以下载最新 DMG。", english: "Version \(version) is available.")
    }

    static func noDMGFound(_ version: String) -> String {
        localized(chinese: "发现新版本 \(version)，但没有找到 DMG 文件。", english: "Version \(version) is available, but no DMG was found.")
    }

    static var downloadLatestDMG: String {
        localized(chinese: "下载最新 DMG", english: "Download Latest DMG")
    }

    static var downloadingLatestDMG: String {
        localized(chinese: "正在下载最新 DMG…", english: "Downloading latest DMG...")
    }

    static func downloadFinished(_ fileName: String) -> String {
        localized(chinese: "已下载到“下载”文件夹：\(fileName)", english: "Downloaded to Downloads: \(fileName)")
    }

    static func updateCheckFailed(_ message: String) -> String {
        localized(chinese: "检查更新失败：\(message)", english: "Update check failed: \(message)")
    }

    static func downloadFailed(_ message: String) -> String {
        localized(chinese: "下载失败：\(message)", english: "Download failed: \(message)")
    }

    static var updateServerUnavailable: String {
        localized(chinese: "更新服务器暂时不可用", english: "The update server is unavailable")
    }

    static var unknownVersion: String {
        localized(chinese: "未知版本", english: "Unknown")
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
    case waitingForPowerAdapter
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
