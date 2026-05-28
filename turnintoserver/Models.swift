import Foundation

enum AppDefaultsKey {
    static let iMessageRecipientAddress = "iMessageRecipientAddress"
    static let verifiedIMessageRecipientAddress = "verifiedIMessageRecipientAddress"
    static let barkPushEndpoint = "barkPushEndpoint"
    static let verifiedBarkPushEndpoint = "verifiedBarkPushEndpoint"
    static let lowBatteryNotificationsEnabled = "lowBatteryNotificationsEnabled"
    static let hotKeysEnabled = "hotKeysEnabled"
    static let serverModeHotKey = "serverModeHotKey"
    static let batteryModeHotKey = "batteryModeHotKey"
    static let serverModeHotKeyDisabled = "serverModeHotKeyDisabled"
    static let batteryModeHotKeyDisabled = "batteryModeHotKeyDisabled"
    static let timedServerModeDurationOptions = "timedServerModeDurationOptions"
    static let timedServerModePreventDisplaySleep = "timedServerModePreventDisplaySleep"
}

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

    static func timedServerModeRemaining(totalSeconds: Int) -> String {
        let clampedSeconds = max(0, totalSeconds)
        let days = clampedSeconds / (24 * 60 * 60)
        let hours = (clampedSeconds % (24 * 60 * 60)) / (60 * 60)
        let minutes = (clampedSeconds % (60 * 60)) / 60
        let seconds = clampedSeconds % 60

        if isChinesePreferred {
            var parts: [String] = []
            if days > 0 {
                parts.append("\(days)天")
            }
            if hours > 0 {
                parts.append("\(hours)小时")
            }
            if minutes > 0 {
                parts.append("\(minutes)分钟")
            }
            parts.append("\(seconds)秒")
            return "剩余 " + parts.joined()
        }

        var parts: [String] = []
        if days > 0 {
            parts.append("\(days)d")
        }
        if hours > 0 {
            parts.append("\(hours)h")
        }
        if minutes > 0 {
            parts.append("\(minutes)m")
        }
        parts.append("\(seconds)s")
        return parts.joined(separator: " ") + " remaining"
    }

    static func timedServerModeDuration(minutes: Int) -> String {
        let clampedMinutes = max(1, minutes)
        let days = clampedMinutes / (24 * 60)
        let hours = (clampedMinutes % (24 * 60)) / 60
        let minutes = clampedMinutes % 60

        if isChinesePreferred {
            var parts: [String] = []
            if days > 0 {
                parts.append("\(days)天")
            }
            if hours > 0 {
                parts.append("\(hours)小时")
            }
            if minutes > 0 {
                parts.append("\(minutes)分钟")
            }
            return parts.joined()
        }

        var parts: [String] = []
        if days > 0 {
            parts.append(days == 1 ? "1 day" : "\(days) days")
        }
        if hours > 0 {
            parts.append(hours == 1 ? "1 hour" : "\(hours) hours")
        }
        if minutes > 0 {
            parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes")
        }
        return parts.joined(separator: " ")
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

    static var timedServerMode: String {
        localized(chinese: "在一段时间内启动", english: "Start for a Duration")
    }

    static var preventTimedServerModeDisplaySleep: String {
        localized(chinese: "阻止屏幕睡眠", english: "Prevent Display Sleep")
    }

    static var timedServerModeSettings: String {
        localized(chinese: "设置…", english: "Settings...")
    }

    static var timedServerModeSettingsTitle: String {
        localized(chinese: "启动时长", english: "Activation Durations")
    }

    static var resetTimedServerModeDurations: String {
        localized(chinese: "重置…", english: "Reset...")
    }

    static var addTimedServerModeDurationTitle: String {
        localized(chinese: "添加时长", english: "Add Duration")
    }

    static var addTimedServerModeDurationMessage: String {
        localized(chinese: "请输入小时和分钟。", english: "Enter hours and minutes.")
    }

    static var addTimedServerModeDurationConfirm: String {
        localized(chinese: "添加", english: "Add")
    }

    static var timedServerModeHoursUnit: String {
        localized(chinese: "小时", english: "h")
    }

    static var timedServerModeMinutesUnit: String {
        localized(chinese: "分钟", english: "min")
    }

    static var invalidTimedServerModeDuration: String {
        localized(chinese: "请输入 1 到 10080 之间的整数分钟。", english: "Enter a whole number from 1 to 10080 minutes.")
    }

    static var invalidTimedServerModeDurationComponents: String {
        localized(
            chinese: "请输入 0 到 168 小时、0 到 59 分钟，且总时长为 1 到 10080 分钟。",
            english: "Enter 0 to 168 hours and 0 to 59 minutes, with a total duration from 1 to 10080 minutes."
        )
    }

    static var timedServerModeEnded: String {
        localized(chinese: "定时已结束", english: "Timed Server Mode ended")
    }

    static var lowBatteryNotifications: String {
        localized(chinese: "推送低电量通知", english: "Low Battery Alerts")
    }

    static var configureLowBatteryNotifications: String {
        localized(chinese: "设置", english: "Set Up")
    }

    static var lowBatteryNotificationsRequireTest: String {
        localized(chinese: "请先在低电量提醒设置里完成至少一个通道的测试。", english: "Test at least one low battery alert channel first.")
    }

    static var launchAtLogin: String {
        localized(chinese: "开机自动启动", english: "Open at Login")
    }

    static var preferences: String {
        localized(chinese: "偏好设置", english: "Preferences")
    }

    static var aboutApplication: String {
        localized(chinese: "关于应用", english: "About turnintoserver")
    }

    static var settings: String {
        localized(chinese: "设置", english: "Settings")
    }

    static var quit: String {
        localized(chinese: "退出", english: "Quit")
    }

    static var edit: String {
        localized(chinese: "编辑", english: "Edit")
    }

    static var cut: String {
        localized(chinese: "剪切", english: "Cut")
    }

    static var copy: String {
        localized(chinese: "复制", english: "Copy")
    }

    static var paste: String {
        localized(chinese: "粘贴", english: "Paste")
    }

    static var selectAll: String {
        localized(chinese: "全选", english: "Select All")
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

    static var quitConfirmationTitle: String {
        localized(chinese: "确认退出 turnintoserver？", english: "Quit turnintoserver?")
    }

    static var quitConfirmationMessage: String {
        localized(
            chinese: "当前检测到 MacBook 已合盖，并且没有外接显示器。退出应用会关闭 Server Mode 并恢复系统睡眠行为，这台 Mac 可能会进入睡眠，远程连接可能会断开。",
            english: "This MacBook appears to be closed with no external display connected. Quitting will turn off Server Mode and restore sleep behavior, which may put this Mac to sleep and disconnect remote sessions."
        )
    }

    static var quitConfirmationContinue: String {
        localized(chinese: "继续退出", english: "Quit")
    }

    static var quitCancelled: String {
        localized(chinese: "已取消退出", english: "Quit cancelled")
    }

    static var batteryRestrictionConfirmationTitle: String {
        localized(chinese: "确认暂停 Server Mode？", english: "Pause Server Mode?")
    }

    static var batteryRestrictionConfirmationMessage: String {
        localized(
            chinese: "当前已切换到电池供电，并且未允许电池模式。MacBook 已合盖且没有外接显示器；暂停 Server Mode 后，这台 Mac 可能会进入睡眠，远程连接可能会断开。",
            english: "This Mac has switched to battery power, and battery mode is not allowed. The MacBook appears to be closed with no external display connected. Pausing Server Mode may put this Mac to sleep and disconnect remote sessions."
        )
    }

    static var batteryRestrictionConfirmationContinue: String {
        localized(chinese: "继续暂停", english: "Pause")
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

    static var enableShortcuts: String {
        localized(chinese: "启用快捷键", english: "Enable Shortcuts")
    }

    static var configureShortcuts: String {
        localized(chinese: "设置", english: "Set Up")
    }

    static var serverModeShortcutLabel: String {
        localized(chinese: "切换 Server Mode", english: "Toggle Server Mode")
    }

    static var batteryModeShortcutLabel: String {
        localized(chinese: "切换电池模式", english: "Toggle Battery Mode")
    }

    static var recordShortcut: String {
        localized(chinese: "录制", english: "Record")
    }

    static var shortcutNotSet: String {
        localized(chinese: "未设置", english: "Not Set")
    }

    static var recordingShortcut: String {
        localized(chinese: "按下新的快捷键…", english: "Press the new shortcut...")
    }

    static var resetShortcuts: String {
        localized(chinese: "恢复默认快捷键", english: "Reset Shortcuts")
    }

    static var shortcutRecordHint: String {
        localized(
            chinese: "录制时至少包含一个修饰键；录制中点击别处会设为未设置。",
            english: "Use at least one modifier key when recording; click away while recording to leave it unset."
        )
    }

    static var shortcutsOn: String {
        localized(chinese: "快捷键已启用", english: "Shortcuts are on")
    }

    static var shortcutsOff: String {
        localized(chinese: "快捷键已关闭", english: "Shortcuts are off")
    }

    static var iMessageSettingsTitle: String {
        localized(chinese: "低电量提醒", english: "Low Battery Alerts")
    }

    static var iMessageChannelTitle: String {
        "iMessage"
    }

    static var barkChannelTitle: String {
        "Bark"
    }

    static var iMessageRecipientPlaceholder: String {
        localized(chinese: "手机号或 Apple ID 邮箱", english: "Phone number or Apple ID email")
    }

    static var barkPushEndpointPlaceholder: String {
        localized(chinese: "Bark 推送地址，例如 https://api.day.app/你的key", english: "Bark push URL, e.g. https://api.day.app/your-key")
    }

    static var testNotificationChannel: String {
        localized(chinese: "测试", english: "Test")
    }

    static var ok: String {
        localized(chinese: "好", english: "OK")
    }

    static var sendTestMessage: String {
        localized(chinese: "测试 iMessage", english: "Test iMessage")
    }

    static var sendBarkTest: String {
        localized(chinese: "测试 Bark", english: "Test Bark")
    }

    static var iMessageSettingsIdle: String {
        localized(
            chinese: "填写 iMessage 或 Bark 任一通道并测试成功后，才能开启低电量提醒。两个都填写时会同时推送。低于 50% 和 20% 时各发送一次。",
            english: "Configure and successfully test iMessage or Bark before enabling alerts. If both are set, both will be used. Sends once below 50% and once below 20%."
        )
    }

    static var iMessageInfoTitle: String {
        "iMessage"
    }

    static var iMessageInfoMessage: String {
        localized(
            chinese: "填写可以接收 iMessage 的手机号或 Apple ID 邮箱，然后点击测试。首次发送时，macOS 可能会要求允许 turnintoserver 控制 Messages。\n\n测试成功后，低电量提醒才可以开启。Server Mode 正在运行、允许电池模式且当前使用电池时，电量低于 50% 和 20% 会各提醒一次。",
            english: "Enter a phone number or Apple ID email that can receive iMessage, then click Test. The first send may ask macOS permission for turnintoserver to control Messages.\n\nAfter a successful test, low battery alerts can be enabled. When Server Mode is running, battery mode is allowed, and this Mac is on battery power, alerts send once below 50% and once below 20%."
        )
    }

    static var barkInfoTitle: String {
        "Bark"
    }

    static var barkInfoMessage: String {
        localized(
            chinese: "填写 Bark 推送地址，例如 https://api.day.app/你的key，然后点击测试。\n\n测试成功后，低电量提醒才可以开启。Server Mode 正在运行、允许电池模式且当前使用电池时，电量低于 50% 和 20% 会各提醒一次。如果 iMessage 和 Bark 都填写并测试成功，会同时推送。",
            english: "Enter your Bark push URL, for example https://api.day.app/your-key, then click Test.\n\nAfter a successful test, low battery alerts can be enabled. When Server Mode is running, battery mode is allowed, and this Mac is on battery power, alerts send once below 50% and once below 20%. If iMessage and Bark are both configured and tested, both will be used."
        )
    }

    static var iMessageRecipientMissing: String {
        localized(chinese: "请先填写 iMessage 收件地址。", english: "Enter an iMessage recipient first.")
    }

    static var iMessageTestSending: String {
        localized(chinese: "正在通过 Messages 发送…", english: "Sending through Messages...")
    }

    static var iMessageTestSent: String {
        localized(chinese: "测试消息已发送。", english: "Test message sent.")
    }

    static var iMessageNeedsRetest: String {
        localized(chinese: "iMessage 地址已修改，需要重新测试。", english: "iMessage address changed; test it again.")
    }

    static func iMessageTestFailed(_ message: String) -> String {
        localized(chinese: "测试发送失败：\(message)", english: "Test send failed: \(message)")
    }

    static func iMessageTestMessage(macName: String) -> String {
        localized(
            chinese: "turnintoserver 测试：\(macName) 的低电量 iMessage 通知已配置成功。",
            english: "turnintoserver test: low battery iMessage alerts are configured on \(macName)."
        )
    }

    static var barkEndpointMissing: String {
        localized(chinese: "请先填写 Bark 推送地址。", english: "Enter a Bark push URL first.")
    }

    static var barkTestSending: String {
        localized(chinese: "正在通过 Bark 发送…", english: "Sending through Bark...")
    }

    static var barkTestSent: String {
        localized(chinese: "Bark 测试已发送。", english: "Bark test sent.")
    }

    static var barkNeedsRetest: String {
        localized(chinese: "Bark 地址已修改，需要重新测试。", english: "Bark URL changed; test it again.")
    }

    static func barkTestFailed(_ message: String) -> String {
        localized(chinese: "Bark 测试失败：\(message)", english: "Bark test failed: \(message)")
    }

    static func barkTestBody(macName: String) -> String {
        localized(
            chinese: "\(macName) 的低电量 Bark 通知已配置成功。",
            english: "Low battery Bark alerts are configured on \(macName)."
        )
    }

    static var memoryTrendLast24Hours: String {
        localized(chinese: "最近 24 小时", english: "Last 24 Hours")
    }

    static var memoryUsageSectionTitle: String {
        localized(chinese: "系统压力", english: "System Pressure")
    }

    static func systemPressureSummary(memory: String, cpu: String) -> String {
        localized(chinese: "\(memory) · CPU \(cpu)", english: "\(memory) · CPU \(cpu)")
    }

    static func memoryTrendCurrent(memory: String, cpu: String) -> String {
        localized(chinese: "现在 \(memory) · CPU \(cpu)", english: "Now \(memory) · CPU \(cpu)")
    }

    static func memoryTrendPeak(memory: String, cpu: String) -> String {
        localized(chinese: "峰值 \(memory) · CPU \(cpu)", english: "Peak \(memory) · CPU \(cpu)")
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
        localized(chinese: "发现新版本 \(version)，正在准备下载。", english: "Version \(version) is available. Preparing to download.")
    }

    static func noDMGFound(_ version: String) -> String {
        localized(chinese: "发现新版本 \(version)，但没有找到 DMG 文件。", english: "Version \(version) is available, but no DMG was found.")
    }

    static var downloadLatestDMG: String {
        localized(chinese: "下载并安装更新", english: "Download and Install")
    }

    static var downloadingLatestDMG: String {
        localized(chinese: "正在下载更新…", english: "Downloading update...")
    }

    static func downloadingUpdateProgress(_ percent: Int) -> String {
        localized(chinese: "正在下载更新…\(percent)%", english: "Downloading update... \(percent)%")
    }

    static var updateReadyToRestart: String {
        localized(chinese: "更新已准备好，重新启动应用后完成安装。", english: "Update is ready. Restart the app to finish installing.")
    }

    static var restartToInstallUpdate: String {
        localized(chinese: "重新启动应用", english: "Restart App")
    }

    static var restartingToInstallUpdate: String {
        localized(chinese: "正在重新启动并安装更新…", english: "Restarting to install update...")
    }

    static var updateInstallCancelled: String {
        localized(chinese: "已取消重新启动，更新尚未安装。", english: "Restart cancelled. The update has not been installed.")
    }

    static func updateInstallFailed(_ message: String) -> String {
        localized(chinese: "安装更新失败：\(message)", english: "Update install failed: \(message)")
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

    static var launchAtLoginUnsupported: String {
        localized(chinese: "开机自动启动需要 macOS 13 或更高版本", english: "Open at Login requires macOS 13 or later")
    }

    static var batteryPowerAllowed: String {
        localized(chinese: "电池供电已允许", english: "Battery power is allowed")
    }

    static var batteryPowerRestricted: String {
        localized(chinese: "电池供电已限制", english: "Battery power is restricted")
    }

    static var lowBatteryNotificationsOn: String {
        localized(chinese: "低电量通知已开启", english: "Low battery alerts are on")
    }

    static var lowBatteryNotificationsOff: String {
        localized(chinese: "低电量通知已关闭", english: "Low battery alerts are off")
    }

    static func launchAtLoginFailed(_ message: String) -> String {
        localized(chinese: "开机启动失败：\(message)", english: "Open at Login failed: \(message)")
    }

    static var commandAlreadyRunning: String {
        localized(chinese: "已有命令执行中", english: "A command is already running")
    }

    static var stopServerModeCancelled: String {
        localized(chinese: "关闭 Server 模式已取消", english: "Turning off Server Mode was cancelled")
    }

    static var pausedWaitingForPowerAdapter: String {
        localized(chinese: "已暂停，等待连接电源适配器", english: "Paused, waiting for a power adapter")
    }

    static var keptRunningOnBatteryForNow: String {
        localized(chinese: "已继续在电池供电下运行", english: "Kept running on battery for now")
    }

    static var serverModeCancelled: String {
        localized(chinese: "Server 模式已取消", english: "Server Mode was cancelled")
    }

    static var waitingForAuthorizationToStart: String {
        localized(chinese: "等待授权启用", english: "Waiting for authorization to start")
    }

    static var waitingForAuthorizationToStop: String {
        localized(chinese: "等待授权关闭", english: "Waiting for authorization to stop")
    }

    static var detectedServerModeEnabled: String {
        localized(chinese: "检测到合盖模式已启用", english: "Detected that closed-lid mode is enabled")
    }

    static var builtInDisplayDimCancelled: String {
        localized(chinese: "内建屏调暗取消", english: "Built-in display dimming was cancelled")
    }

    static func builtInDisplayDimFailed(_ message: String) -> String {
        localized(chinese: "内建屏调暗失败：\(message)", english: "Built-in display dimming failed: \(message)")
    }

    static var builtInDisplayBrightnessRestoreCancelled: String {
        localized(chinese: "内建屏亮度恢复取消", english: "Built-in display brightness restore was cancelled")
    }

    static func builtInDisplayBrightnessRestoreFailed(_ message: String) -> String {
        localized(chinese: "内建屏亮度恢复失败：\(message)", english: "Built-in display brightness restore failed: \(message)")
    }

    static func success(_ message: String) -> String {
        localized(chinese: "成功：\(message)", english: "Success: \(message)")
    }

    static var userCancelledAuthorization: String {
        localized(chinese: "用户取消授权", english: "Authorization was cancelled")
    }

    static func failure(_ message: String) -> String {
        localized(chinese: "失败：\(message)", english: "Failed: \(message)")
    }

    static var startedOnBatteryPower: String {
        localized(chinese: "已在电池供电下启动", english: "Started on battery power")
    }

    static var startedOnPowerAdapter: String {
        localized(chinese: "已在接电源下启动", english: "Started on power adapter")
    }

    static var startedServerMode: String {
        localized(chinese: "已启动", english: "Started")
    }

    static var restoredClosedLidSleep: String {
        localized(chinese: "已恢复合盖睡眠", english: "Closed-lid sleep has been restored")
    }

    static var serverModeAlreadyRunning: String {
        localized(chinese: "Server 模式已在运行", english: "Server Mode is already running")
    }

    static func caffeinateLaunchFailed(_ message: String) -> String {
        localized(chinese: "无法启动 caffeinate：\(message)", english: "Could not start caffeinate: \(message)")
    }

    static var caffeinateExited: String {
        localized(chinese: "caffeinate 已退出", english: "caffeinate exited")
    }

    static var commandFailed: String {
        localized(chinese: "命令执行失败", english: "Command failed")
    }

    static var unsupportedUserName: String {
        localized(chinese: "当前用户名包含 sudoers 不支持的字符", english: "The current username contains characters unsupported by sudoers")
    }

    static var builtInDisplayControlUnavailable: String {
        localized(chinese: "无法载入内建显示器控制", english: "Could not load built-in display controls")
    }

    static var noOnlineBuiltInDisplay: String {
        localized(chinese: "未检测到在线内建屏", english: "No online built-in display was detected")
    }

    static func readBuiltInDisplayBrightnessFailed(_ code: Int32) -> String {
        localized(chinese: "读取内建屏亮度失败：\(code)", english: "Reading built-in display brightness failed: \(code)")
    }

    static func dimBuiltInDisplayFailed(_ code: Int32) -> String {
        localized(chinese: "调暗内建屏失败：\(code)", english: "Dimming the built-in display failed: \(code)")
    }

    static var builtInDisplayDimmed: String {
        localized(chinese: "已调暗内建屏", english: "Built-in display dimmed")
    }

    static var couldNotDimBuiltInDisplay: String {
        localized(chinese: "未能调暗内建屏", english: "Could not dim the built-in display")
    }

    static var noBuiltInDisplayBrightnessRestoreNeeded: String {
        localized(chinese: "无需恢复内建屏亮度", english: "No built-in display brightness restore needed")
    }

    static func restoreBuiltInDisplayBrightnessFailed(_ code: Int32) -> String {
        localized(chinese: "恢复内建屏亮度失败：\(code)", english: "Restoring built-in display brightness failed: \(code)")
    }

    static var builtInDisplayBrightnessRestored: String {
        localized(chinese: "已恢复内建屏亮度", english: "Built-in display brightness restored")
    }

    static var couldNotRestoreBuiltInDisplayBrightness: String {
        localized(chinese: "未能恢复内建屏亮度", english: "Could not restore built-in display brightness")
    }

    static var messagesDidNotSend: String {
        localized(chinese: "Messages 未能发送消息。", english: "Messages did not send the message.")
    }

    static var barkDidNotSend: String {
        localized(chinese: "Bark 未能发送消息。", english: "Bark did not send the message.")
    }

    static func lowBatteryIMessage(threshold: Int, batteryPercentage: Int, macName: String) -> String {
        localized(
            chinese: "turnintoserver 警告：\(macName) 正在使用电池运行 Server Mode，电量已低于 \(threshold)%（当前 \(batteryPercentage)%）。请尽快接入电源。",
            english: "turnintoserver alert: \(macName) is running Server Mode on battery and is below \(threshold)% power (currently \(batteryPercentage)%). Please connect power soon."
        )
    }

    static func lowBatteryNotificationTitle(threshold: Int) -> String {
        localized(chinese: "低电量提醒：低于 \(threshold)%", english: "Low Battery Alert: Below \(threshold)%")
    }

    static func lowBatteryNotificationSent(threshold: Int, channels: [String]) -> String {
        let channelList = channels.joined(separator: ", ")
        return localized(
            chinese: "已发送低电量通知：低于 \(threshold)%（\(channelList)）",
            english: "Low battery alert sent below \(threshold)% (\(channelList))"
        )
    }

    static func lowBatteryNotificationFailed(_ message: String) -> String {
        localized(chinese: "低电量通知发送失败：\(message)", english: "Low battery alert failed: \(message)")
    }

    static var lowBatteryNotificationChannelMissing: String {
        localized(chinese: "请先在低电量提醒设置里填写 iMessage 或 Bark 通道。", english: "Configure an iMessage or Bark channel in low battery alert settings first.")
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

struct LowBatteryNotificationReadiness: Equatable {
    var canEnable: Bool
    var iMessageConfigured = false
    var iMessageVerified = false
    var barkConfigured = false
    var barkVerified = false
}

enum PowerManagerError: LocalizedError {
    case unsupportedUserName

    var errorDescription: String? {
        switch self {
        case .unsupportedUserName:
            return AppText.unsupportedUserName
        }
    }
}

enum IMessageNotifier {
    static func send(message: String, to recipient: String) async throws {
        let trimmedRecipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRecipient.isEmpty else {
            throw IMessageNotifierError.missingRecipient
        }

        let script = """
        tell application "Messages"
            set iMessageAccounts to every account whose service type is iMessage and enabled is true
            if (count of iMessageAccounts) is 0 then error "No enabled iMessage account is available in Messages."
            set targetAccount to item 1 of iMessageAccounts
            set targetParticipant to participant \(appleScriptString(trimmedRecipient)) of targetAccount
            send \(appleScriptString(message)) to targetParticipant
        end tell
        """

        let result = try await ShellRunner.run("/usr/bin/osascript", arguments: ["-e", script])
        guard result.exitCode == 0 else {
            throw IMessageNotifierError.sendFailed(result.combinedOutput)
        }
    }

    static var defaultMacName: String {
        Host.current().localizedName ?? "Mac"
    }

    private static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }
}

enum IMessageNotifierError: LocalizedError {
    case missingRecipient
    case sendFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRecipient:
            return AppText.iMessageRecipientMissing
        case .sendFailed(let message):
            return message.isEmpty ? AppText.messagesDidNotSend : message
        }
    }
}

enum BarkNotifier {
    static func send(title: String, body: String, endpoint: String) async throws {
        let requestURL = try normalizedEndpoint(endpoint)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("turnintoserver", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "title": title,
                "body": body,
                "group": "turnintoserver"
            ],
            options: []
        )

        let (data, response) = try await fetchData(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw BarkNotifierError.sendFailed(AppText.barkDidNotSend)
        }

        if let barkResponse = try? JSONDecoder().decode(BarkResponse.self, from: data),
           let code = barkResponse.code,
           code != 200 {
            throw BarkNotifierError.sendFailed(barkResponse.message ?? AppText.barkDidNotSend)
        }
    }

    private struct BarkResponse: Decodable {
        let code: Int?
        let message: String?
    }

    private static func normalizedEndpoint(_ endpoint: String) throws -> URL {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else {
            throw BarkNotifierError.missingEndpoint
        }

        let endpointWithScheme: String
        if trimmedEndpoint.contains("://") {
            endpointWithScheme = trimmedEndpoint
        } else {
            endpointWithScheme = "https://\(trimmedEndpoint)"
        }

        guard let url = URL(string: endpointWithScheme),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            throw BarkNotifierError.invalidEndpoint
        }

        return url
    }

    private static func fetchData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }

                continuation.resume(returning: (data, response))
            }
            .resume()
        }
    }
}

enum BarkNotifierError: LocalizedError {
    case missingEndpoint
    case invalidEndpoint
    case sendFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return AppText.barkEndpointMissing
        case .invalidEndpoint:
            return AppText.barkDidNotSend
        case .sendFailed(let message):
            return message.isEmpty ? AppText.barkDidNotSend : message
        }
    }
}
