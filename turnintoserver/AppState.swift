import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    private enum DefaultsKey {
        static let allowBatteryServerMode = "allowBatteryServerMode"
        static let lastCommandStatus = "lastCommandStatus"
        static let lastKnownPowerSource = "lastKnownPowerSource"
        static let serverModeRequested = "serverModeRequested"
        static let serverModeStartedAt = "serverModeStartedAt"
    }

    @Published private(set) var powerSource: PowerSource {
        didSet {
            defaults.set(powerSource.rawValue, forKey: DefaultsKey.lastKnownPowerSource)
            notifyStatusIconShouldRefresh()
        }
    }

    @Published private(set) var lidState: LidState = .unknown
    @Published private(set) var serverModeActive = false {
        didSet {
            updateServerModeRuntimeTracking()
            notifyStatusIconShouldRefresh()
            Task { @MainActor in
                await evaluateLowBatteryNotification()
            }
        }
    }
    @Published private(set) var serverModeRequested = false {
        didSet {
            defaults.set(serverModeRequested, forKey: DefaultsKey.serverModeRequested)
            notifyStatusIconShouldRefresh()
        }
    }
    @Published private(set) var lastCommandStatus: String {
        didSet {
            defaults.set(lastCommandStatus, forKey: DefaultsKey.lastCommandStatus)
        }
    }

    @Published private(set) var isCommandRunning = false {
        didSet {
            notifyMenuShouldRefresh()
        }
    }
    @Published private(set) var serverModeRuntimeDisplay: String? {
        didSet {
            notifyMenuShouldRefresh()
        }
    }

    @Published private(set) var allowBatteryServerMode: Bool {
        didSet {
            defaults.set(allowBatteryServerMode, forKey: DefaultsKey.allowBatteryServerMode)
            notifyStatusIconShouldRefresh()
        }
    }

    @Published private(set) var launchAtLoginEnabled = false {
        didSet {
            notifyMenuShouldRefresh()
        }
    }
    @Published private(set) var isLaunchAtLoginChanging = false {
        didSet {
            notifyMenuShouldRefresh()
        }
    }

    @Published private(set) var lowBatteryNotificationsEnabled: Bool {
        didSet {
            defaults.set(lowBatteryNotificationsEnabled, forKey: AppDefaultsKey.lowBatteryNotificationsEnabled)
            notifyMenuShouldRefresh()
        }
    }

    @Published private(set) var hotKeysEnabled: Bool {
        didSet {
            defaults.set(hotKeysEnabled, forKey: AppDefaultsKey.hotKeysEnabled)
            NotificationCenter.default.post(name: .turnIntoServerHotKeysDidChange, object: nil)
            notifyMenuShouldRefresh()
        }
    }

    private let defaults: UserDefaults
    private let monitor: PowerSourceMonitor
    private let lidMonitor: LidStateMonitor
    private let powerManager: PowerManager
    private let launchAtLoginManager: LaunchAtLoginManager
    private var hasStarted = false
    private var wakeObserver: NSObjectProtocol?
    private var screensWakeObserver: NSObjectProtocol?
    private var didHandleBuiltInDisplayForClosedLid = false
    private var isBuiltInDisplayCommandRunning = false
    private var serverModeStartedAt: Date?
    private var runtimeTimer: Timer?
    private var batteryNotificationTimer: Timer?
    private var sentLowBatteryThresholds = Set<Int>()

    init(
        defaults: UserDefaults = .standard,
        monitor: PowerSourceMonitor = PowerSourceMonitor(),
        lidMonitor: LidStateMonitor = LidStateMonitor(),
        powerManager: PowerManager? = nil,
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager()
    ) {
        self.defaults = defaults
        self.monitor = monitor
        self.lidMonitor = lidMonitor
        self.powerManager = powerManager ?? PowerManager()
        self.launchAtLoginManager = launchAtLoginManager

        defaults.removeObject(forKey: "serverModeActive")
        defaults.removeObject(forKey: "savedPowerSettingsSnapshot")
        allowBatteryServerMode = defaults.bool(forKey: DefaultsKey.allowBatteryServerMode)
        let savedLowBatteryNotificationsEnabled = defaults.bool(forKey: AppDefaultsKey.lowBatteryNotificationsEnabled)
        let canEnableSavedLowBatteryNotifications = Self.canEnableLowBatteryNotifications(defaults: defaults)
        lowBatteryNotificationsEnabled = savedLowBatteryNotificationsEnabled && canEnableSavedLowBatteryNotifications
        hotKeysEnabled = defaults.object(forKey: AppDefaultsKey.hotKeysEnabled) as? Bool ?? true
        serverModeRequested = defaults.bool(forKey: DefaultsKey.serverModeRequested)

        let savedSource = defaults.string(forKey: DefaultsKey.lastKnownPowerSource)
        powerSource = savedSource.flatMap(PowerSource.init(rawValue:)) ?? .unknown
        lastCommandStatus = AppText.notStarted
        serverModeStartedAt = defaults.object(forKey: DefaultsKey.serverModeStartedAt) as? Date

        if savedLowBatteryNotificationsEnabled && !canEnableSavedLowBatteryNotifications {
            defaults.set(false, forKey: AppDefaultsKey.lowBatteryNotificationsEnabled)
        }

        refreshLaunchAtLoginEnabled()
    }

    var menuBarStatusTitle: String {
        if serverModeActive || (serverModeRequested && !isWaitingForPowerAdapter) {
            return allowBatteryServerMode
                ? AppText.serverModeOnBatteryAllowed
                : AppText.serverModeOnPowerOnly
        }

        if isWaitingForPowerAdapter {
            return AppText.waitingForPowerAdapter
        }

        return "turnintoserver"
    }

    var menuBarIconStyle: MenuBarIconStyle {
        if serverModeActive || (serverModeRequested && !isWaitingForPowerAdapter) {
            return allowBatteryServerMode ? .serverModeBatteryAllowed : .serverModePowerOnly
        }

        if isWaitingForPowerAdapter {
            return .waitingForPowerAdapter
        }

        return .idle
    }

    var serverModeActionTitle: String {
        if serverModeRequested || serverModeActive {
            return AppText.stopServerMode
        }

        return AppText.startServerMode
    }

    var serverModeActionSystemImage: String {
        serverModeRequested || serverModeActive ? "power" : "server.rack"
    }

    var launchAtLoginSupported: Bool {
        launchAtLoginManager.isSupported
    }

    var statusSummaryDisplay: String {
        guard serverModeRequested else {
            return AppText.notStarted
        }

        if powerSource == .batteryPower, !allowBatteryServerMode {
            return AppText.connectPowerToKeepRunningWithLidClosed
        }

        return AppText.keepsRunningWithLidClosed
    }

    private func updateServerModeRuntimeTracking() {
        guard serverModeActive else {
            stopServerModeRuntimeTimer()
            clearServerModeStartedAt()
            updateServerModeRuntimeDisplay()
            return
        }

        if serverModeStartedAt == nil {
            setServerModeStartedAt(Date())
        }

        startServerModeRuntimeTimer()
        updateServerModeRuntimeDisplay()
    }

    private func startServerModeRuntimeTimer() {
        guard runtimeTimer == nil else {
            return
        }

        runtimeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateServerModeRuntimeDisplay()
            }
        }
    }

    private func stopServerModeRuntimeTimer() {
        runtimeTimer?.invalidate()
        runtimeTimer = nil
    }

    private func setServerModeStartedAt(_ date: Date) {
        serverModeStartedAt = date
        defaults.set(date, forKey: DefaultsKey.serverModeStartedAt)
    }

    private func clearServerModeStartedAt() {
        serverModeStartedAt = nil
        defaults.removeObject(forKey: DefaultsKey.serverModeStartedAt)
    }

    private func updateServerModeRuntimeDisplay() {
        guard serverModeActive, let serverModeStartedAt else {
            serverModeRuntimeDisplay = nil
            return
        }

        let elapsedSeconds = max(0, Int(Date().timeIntervalSince(serverModeStartedAt)))
        serverModeRuntimeDisplay = AppText.serverModeRuntime(totalMinutes: elapsedSeconds / 60)
    }

    private var isWaitingForPowerAdapter: Bool {
        serverModeRequested && !serverModeActive && powerSource == .batteryPower && !allowBatteryServerMode
    }

    private func notifyStatusIconShouldRefresh() {
        NotificationCenter.default.post(name: .turnIntoServerStatusIconShouldRefresh, object: self)
        notifyMenuShouldRefresh()
    }

    private func notifyMenuShouldRefresh() {
        NotificationCenter.default.post(name: .turnIntoServerMenuShouldRefresh, object: self)
    }

    func start() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        startWakeObservers()
        startBatteryNotificationTimer()

        monitor.start { [weak self] source in
            self?.handlePowerSourceUpdate(source)
        }

        lidMonitor.start { [weak self] state in
            self?.handleLidStateUpdate(state)
        }

        Task {
            await refreshServerModeStatus()
        }
    }

    func setAllowBatteryServerMode(_ isEnabled: Bool) {
        guard allowBatteryServerMode != isEnabled else {
            return
        }

        allowBatteryServerMode = isEnabled
        lastCommandStatus = isEnabled ? AppText.batteryPowerAllowed : AppText.batteryPowerRestricted

        Task {
            if serverModeRequested {
                await reconcileServerMode()
            }
            await evaluateLowBatteryNotification()
        }
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        guard launchAtLoginSupported else {
            launchAtLoginEnabled = false
            lastCommandStatus = AppText.launchAtLoginUnsupported
            return
        }

        guard !isLaunchAtLoginChanging else {
            return
        }

        let previousEnabled = launchAtLoginEnabled
        isLaunchAtLoginChanging = true
        launchAtLoginEnabled = isEnabled

        defer {
            isLaunchAtLoginChanging = false
        }

        do {
            try launchAtLoginManager.setEnabled(isEnabled)
            refreshLaunchAtLoginEnabled()

            if let statusMessage = launchAtLoginManager.attentionMessage {
                lastCommandStatus = statusMessage
            }
        } catch {
            launchAtLoginEnabled = previousEnabled
            refreshLaunchAtLoginEnabled()
            lastCommandStatus = AppText.launchAtLoginFailed(error.localizedDescription)
        }
    }

    func refreshLaunchAtLoginStatus() {
        refreshLaunchAtLoginEnabled()

        if let statusMessage = launchAtLoginManager.attentionMessage {
            lastCommandStatus = statusMessage
        }
    }

    private func refreshLaunchAtLoginEnabled() {
        launchAtLoginEnabled = launchAtLoginManager.isEnabled
    }

    func toggleServerMode() async {
        guard !isCommandRunning else {
            lastCommandStatus = AppText.commandAlreadyRunning
            return
        }

        if serverModeRequested || serverModeActive {
            if await needsClosedLidStopConfirmation(),
               !confirmStopServerModeForClosedLidWithoutExternalDisplay() {
                lastCommandStatus = AppText.stopServerModeCancelled
                return
            }

            await disableServerMode()
        } else {
            serverModeRequested = true
            await reconcileServerMode()
        }
    }

    private func needsClosedLidStopConfirmation() async -> Bool {
        guard serverModeActive else {
            return false
        }

        let currentState = await currentLidState()
        guard currentState == .closed else {
            return false
        }

        return !BuiltInDisplayDimmer.hasOnlineExternalDisplay()
    }

    private func confirmStopServerModeForClosedLidWithoutExternalDisplay() -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppText.stopServerModeConfirmationTitle
        alert.informativeText = AppText.stopServerModeConfirmationMessage
        alert.addButton(withTitle: AppText.stopServerModeConfirmationContinue)
        alert.addButton(withTitle: AppText.cancel)

        return alert.runModal() == .alertFirstButtonReturn
    }

    func toggleBatteryServerMode() {
        guard !isCommandRunning else {
            lastCommandStatus = AppText.commandAlreadyRunning
            return
        }

        setAllowBatteryServerMode(!allowBatteryServerMode)
    }

    func toggleLowBatteryNotifications() {
        setLowBatteryNotificationsEnabled(!lowBatteryNotificationsEnabled)
    }

    func toggleHotKeysEnabled() {
        setHotKeysEnabled(!hotKeysEnabled)
    }

    func setHotKeysEnabled(_ isEnabled: Bool) {
        guard hotKeysEnabled != isEnabled else {
            return
        }

        hotKeysEnabled = isEnabled
        lastCommandStatus = isEnabled ? AppText.shortcutsOn : AppText.shortcutsOff
    }

    func setLowBatteryNotificationsEnabled(_ isEnabled: Bool) {
        guard lowBatteryNotificationsEnabled != isEnabled else {
            return
        }

        guard !isEnabled || Self.canEnableLowBatteryNotifications(defaults: defaults) else {
            lowBatteryNotificationsEnabled = false
            lastCommandStatus = AppText.lowBatteryNotificationsRequireTest
            sentLowBatteryThresholds.removeAll()
            return
        }

        lowBatteryNotificationsEnabled = isEnabled
        if isEnabled {
            lastCommandStatus = AppText.lowBatteryNotificationsOn
            Task {
                await evaluateLowBatteryNotification()
            }
        } else {
            lastCommandStatus = AppText.lowBatteryNotificationsOff
            sentLowBatteryThresholds.removeAll()
        }
    }

    static func canEnableLowBatteryNotifications(defaults: UserDefaults = .standard) -> Bool {
        lowBatteryNotificationReadiness(defaults: defaults).canEnable
    }

    static func lowBatteryNotificationReadiness(defaults: UserDefaults = .standard) -> LowBatteryNotificationReadiness {
        let recipient = defaults.string(forKey: AppDefaultsKey.iMessageRecipientAddress)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let verifiedRecipient = defaults.string(forKey: AppDefaultsKey.verifiedIMessageRecipientAddress)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let barkEndpoint = defaults.string(forKey: AppDefaultsKey.barkPushEndpoint)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let verifiedBarkEndpoint = defaults.string(forKey: AppDefaultsKey.verifiedBarkPushEndpoint)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let iMessageConfigured = !recipient.isEmpty
        let barkConfigured = !barkEndpoint.isEmpty
        let iMessageVerified = iMessageConfigured && recipient == verifiedRecipient
        let barkVerified = barkConfigured && barkEndpoint == verifiedBarkEndpoint

        guard iMessageConfigured || barkConfigured else {
            return LowBatteryNotificationReadiness(canEnable: false)
        }

        return LowBatteryNotificationReadiness(
            canEnable: (!iMessageConfigured || iMessageVerified) && (!barkConfigured || barkVerified),
            iMessageConfigured: iMessageConfigured,
            iMessageVerified: iMessageVerified,
            barkConfigured: barkConfigured,
            barkVerified: barkVerified
        )
    }

    func prepareForQuit() async -> Bool {
        serverModeRequested = false

        if serverModeActive {
            await stopServerMode(clearRequest: true)
        }

        return !serverModeActive
    }

    private func reconcileServerMode() async {
        guard serverModeRequested else {
            if serverModeActive {
                await stopServerMode(clearRequest: false)
            }

            return
        }

        let currentSource = await currentPowerSource()

        guard canRunServerMode(on: currentSource) else {
            if serverModeActive {
                await stopServerMode(clearRequest: false, successMessage: AppText.pausedWaitingForPowerAdapter)
            } else {
                lastCommandStatus = AppText.waitingForPowerAdapter
            }

            return
        }

        guard !serverModeActive else {
            return
        }

        await startServerMode(powerSource: currentSource)
    }

    private func disableServerMode() async {
        if serverModeActive {
            await stopServerMode(clearRequest: true)
        } else {
            serverModeRequested = false
            lastCommandStatus = AppText.serverModeCancelled
        }
    }

    private func startServerMode(powerSource: PowerSource) async {
        guard beginCommand(waitingStatus: AppText.waitingForAuthorizationToStart) else {
            return
        }

        let result = await powerManager.enableServerMode(powerSource: powerSource)
        applyStart(result)
        finishCommand()

        if case .success = result {
            await dimClosedLidBuiltInDisplayIfNeeded()
        }
    }

    private func stopServerMode(clearRequest: Bool, successMessage: String? = nil) async {
        guard beginCommand(waitingStatus: AppText.waitingForAuthorizationToStop) else {
            return
        }

        let previousRequest = serverModeRequested
        if clearRequest {
            serverModeRequested = false
        }

        let result = await powerManager.restoreSleepSettings()
        applyStop(
            result,
            clearRequest: clearRequest,
            previousRequest: previousRequest,
            successMessage: successMessage
        )
        finishCommand()
    }

    private func refreshServerModeStatus() async {
        let currentSource = await currentPowerSource()
        let isSleepDisabled = await powerManager.detectSleepDisabled()
        let shouldRestoreRequestedMode = serverModeRequested
        serverModeActive = isSleepDisabled
        serverModeRequested = isSleepDisabled || shouldRestoreRequestedMode

        if isSleepDisabled {
            powerManager.adoptExistingServerMode(powerSource: currentSource)
            lastCommandStatus = AppText.detectedServerModeEnabled

            if !canRunServerMode(on: currentSource), !isCommandRunning {
                await reconcileServerMode()
            }
        } else if shouldRestoreRequestedMode, !isCommandRunning {
            await reconcileServerMode()
        }

        if serverModeActive, !isCommandRunning {
            await dimClosedLidBuiltInDisplayIfNeeded()
        }

        await evaluateLowBatteryNotification()
    }

    private func currentPowerSource() async -> PowerSource {
        let detectedSource = await monitor.detectPowerSource()
        powerSource = detectedSource
        return detectedSource
    }

    private func currentLidState() async -> LidState {
        let detectedState = await lidMonitor.detectLidState()
        lidState = detectedState
        return detectedState
    }

    private func handlePowerSourceUpdate(_ newSource: PowerSource) {
        let oldSource = powerSource
        powerSource = newSource

        guard (serverModeRequested || serverModeActive), !isCommandRunning else {
            return
        }

        let activeButDisallowed = serverModeActive && !canRunServerMode(on: newSource)
        let shouldReconcile = oldSource != newSource
            || isWaitingForPowerAdapter
            || (newSource == .acPower && !serverModeActive)
            || activeButDisallowed

        guard shouldReconcile else {
            return
        }

        Task {
            await reconcileServerMode()
            await evaluateLowBatteryNotification()
        }
    }

    private func handleLidStateUpdate(_ newState: LidState) {
        let oldState = lidState
        lidState = newState

        guard newState == .closed else {
            if oldState == .closed {
                didHandleBuiltInDisplayForClosedLid = false
                restoreBuiltInDisplayBrightnessIfNeeded()
            }
            return
        }

        guard serverModeActive, !isCommandRunning else {
            return
        }

        Task {
            await dimClosedLidBuiltInDisplayIfNeeded()
        }
    }

    private func startWakeObservers() {
        guard wakeObserver == nil, screensWakeObserver == nil else {
            return
        }

        let notificationCenter = NSWorkspace.shared.notificationCenter
        wakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleWake()
            }
        }

        screensWakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleWake()
            }
        }
    }

    private func handleWake() async {
        guard (serverModeRequested || serverModeActive), !isCommandRunning else {
            return
        }

        _ = await currentPowerSource()
        await reconcileServerMode()
        await dimClosedLidBuiltInDisplayIfNeeded(force: true)
        await evaluateLowBatteryNotification()
    }

    private func startBatteryNotificationTimer() {
        guard batteryNotificationTimer == nil else {
            return
        }

        batteryNotificationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.evaluateLowBatteryNotification()
            }
        }
    }

    private func evaluateLowBatteryNotification() async {
        guard lowBatteryNotificationsEnabled,
              Self.canEnableLowBatteryNotifications(defaults: defaults),
              serverModeActive,
              allowBatteryServerMode,
              powerSource == .batteryPower else {
            sentLowBatteryThresholds.removeAll()
            return
        }

        guard let batteryPercentage = monitor.detectBatteryPercentage() else {
            return
        }

        let threshold: Int?
        if batteryPercentage <= 20 {
            threshold = 20
        } else if batteryPercentage <= 50 {
            threshold = 50
        } else {
            threshold = nil
        }

        guard let threshold, !sentLowBatteryThresholds.contains(threshold) else {
            return
        }

        let recipient = defaults.string(forKey: AppDefaultsKey.iMessageRecipientAddress)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let barkEndpoint = defaults.string(forKey: AppDefaultsKey.barkPushEndpoint)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !recipient.isEmpty || !barkEndpoint.isEmpty else {
            lastCommandStatus = AppText.lowBatteryNotificationChannelMissing
            return
        }

        sentLowBatteryThresholds.insert(threshold)

        let title = AppText.lowBatteryNotificationTitle(threshold: threshold)
        let message = AppText.lowBatteryIMessage(
            threshold: threshold,
            batteryPercentage: batteryPercentage,
            macName: IMessageNotifier.defaultMacName
        )

        var sentChannels: [String] = []
        var failedChannels: [String] = []

        if !recipient.isEmpty {
            do {
                try await IMessageNotifier.send(message: message, to: recipient)
                sentChannels.append("iMessage")
            } catch {
                failedChannels.append("iMessage: \(error.localizedDescription)")
            }
        }

        if !barkEndpoint.isEmpty {
            do {
                try await BarkNotifier.send(title: title, body: message, endpoint: barkEndpoint)
                sentChannels.append("Bark")
            } catch {
                failedChannels.append("Bark: \(error.localizedDescription)")
            }
        }

        if failedChannels.isEmpty, !sentChannels.isEmpty {
            lastCommandStatus = AppText.lowBatteryNotificationSent(threshold: threshold, channels: sentChannels)
        } else if sentChannels.isEmpty {
            lastCommandStatus = AppText.lowBatteryNotificationFailed(failedChannels.joined(separator: " / "))
        } else {
            let detail = failedChannels.joined(separator: " / ")
            lastCommandStatus = AppText.lowBatteryNotificationFailed(detail)
        }
    }

    private func dimClosedLidBuiltInDisplayIfNeeded(force: Bool = false) async {
        guard serverModeActive else {
            return
        }

        let currentState = await currentLidState()
        guard currentState == .closed else {
            didHandleBuiltInDisplayForClosedLid = false
            restoreBuiltInDisplayBrightnessIfNeeded()
            return
        }

        guard force || !didHandleBuiltInDisplayForClosedLid else {
            return
        }

        guard !isBuiltInDisplayCommandRunning else {
            return
        }

        isBuiltInDisplayCommandRunning = true
        let result = powerManager.dimBuiltInDisplayForClosedLid()
        isBuiltInDisplayCommandRunning = false

        switch result {
        case .success(let message):
            didHandleBuiltInDisplayForClosedLid = true
            lastCommandStatus = message
        case .userCancelled:
            didHandleBuiltInDisplayForClosedLid = false
            lastCommandStatus = AppText.builtInDisplayDimCancelled
        case .failure(let message):
            didHandleBuiltInDisplayForClosedLid = false
            lastCommandStatus = AppText.builtInDisplayDimFailed(message)
        }
    }

    private func restoreBuiltInDisplayBrightnessIfNeeded() {
        guard !isBuiltInDisplayCommandRunning else {
            return
        }

        isBuiltInDisplayCommandRunning = true
        let result = powerManager.restoreBuiltInDisplayBrightness()
        isBuiltInDisplayCommandRunning = false

        switch result {
        case .success(let message):
            lastCommandStatus = message
        case .userCancelled:
            lastCommandStatus = AppText.builtInDisplayBrightnessRestoreCancelled
        case .failure(let message):
            lastCommandStatus = AppText.builtInDisplayBrightnessRestoreFailed(message)
        }
    }

    private func beginCommand(waitingStatus: String) -> Bool {
        guard !isCommandRunning else {
            lastCommandStatus = AppText.commandAlreadyRunning
            return false
        }

        isCommandRunning = true
        lastCommandStatus = waitingStatus
        return true
    }

    private func finishCommand() {
        isCommandRunning = false
    }

    private func applyStart(_ result: PowerCommandResult) {
        switch result {
        case .success(let message):
            serverModeRequested = true
            serverModeActive = true
            lastCommandStatus = AppText.success(message)
        case .userCancelled:
            serverModeRequested = false
            serverModeActive = false
            lastCommandStatus = AppText.userCancelledAuthorization
        case .failure(let message):
            serverModeRequested = false
            serverModeActive = false
            lastCommandStatus = AppText.failure(message)
        }
    }

    private func applyStop(
        _ result: PowerCommandResult,
        clearRequest: Bool,
        previousRequest: Bool,
        successMessage: String?
    ) {
        switch result {
        case .success(let message):
            serverModeActive = false
            didHandleBuiltInDisplayForClosedLid = false
            restoreBuiltInDisplayBrightnessIfNeeded()
            if !clearRequest {
                serverModeRequested = previousRequest
            }
            lastCommandStatus = AppText.success(successMessage ?? message)
        case .userCancelled:
            if clearRequest {
                serverModeRequested = previousRequest
            }
            lastCommandStatus = AppText.userCancelledAuthorization
        case .failure(let message):
            if clearRequest {
                serverModeRequested = previousRequest
            }
            lastCommandStatus = AppText.failure(message)
        }
    }

    private func canRunServerMode(on source: PowerSource) -> Bool {
        source != .batteryPower || allowBatteryServerMode
    }
}

struct LaunchAtLoginManager {
    var isSupported: Bool {
        if #available(macOS 13.0, *) {
            return true
        }

        return false
    }

    var isEnabled: Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }

        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    var statusMessage: String {
        guard #available(macOS 13.0, *) else {
            return AppText.launchAtLoginUnsupported
        }

        let status = SMAppService.mainApp.status
        switch status {
        case .enabled:
            return AppText.launchAtLoginOn
        case .notRegistered:
            return AppText.launchAtLoginOff
        case .requiresApproval:
            return AppText.launchAtLoginRequiresApproval
        case .notFound:
            return AppText.launchAtLoginAppNotFound
        @unknown default:
            return AppText.launchAtLoginUnknown
        }
    }

    var attentionMessage: String? {
        guard #available(macOS 13.0, *) else {
            return nil
        }

        let status = SMAppService.mainApp.status
        switch status {
        case .requiresApproval, .notFound:
            return statusMessage
        case .enabled, .notRegistered:
            return nil
        @unknown default:
            return statusMessage
        }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            return
        }

        let service = SMAppService.mainApp

        if isEnabled {
            guard service.status != .enabled, service.status != .requiresApproval else {
                return
            }

            try service.register()
        } else {
            guard service.status != .notRegistered, service.status != .notFound else {
                return
            }

            try service.unregister()
        }
    }
}
