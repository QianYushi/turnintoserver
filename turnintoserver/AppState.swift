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
        static let serverModeRuntimeHeartbeatAt = "serverModeRuntimeHeartbeatAt"
        static let timedServerModeEndDate = "timedServerModeEndDate"
        static let timedServerModeSelectedDurationMinutes = "timedServerModeSelectedDurationMinutes"
    }

    static let builtInTimedServerModeDurationOptions = [30, 60, 120, 180, 360, 720]

    private static let minimumTimedServerModeDurationMinutes = 1
    private static let maximumTimedServerModeDurationMinutes = 7 * 24 * 60
    private static let maximumSavedRuntimeHeartbeatAge: TimeInterval = 5 * 60
    private static let topMemoryAppsRefreshInterval: TimeInterval = 2

    @Published private(set) var powerSource: PowerSource {
        didSet {
            defaults.set(powerSource.rawValue, forKey: DefaultsKey.lastKnownPowerSource)
            notifyStatusIconShouldRefresh()
        }
    }

    @Published private(set) var lidState: LidState = .unknown {
        didSet {
            if oldValue != lidState {
                updateTimedDisplayAwakeAssertion()
            }
        }
    }
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
    @Published private(set) var timedServerModeEndDate: Date? {
        didSet {
            if let timedServerModeEndDate {
                defaults.set(timedServerModeEndDate, forKey: DefaultsKey.timedServerModeEndDate)
            } else {
                defaults.removeObject(forKey: DefaultsKey.timedServerModeEndDate)
            }
            updateTimedDisplayAwakeAssertion()
            notifyMenuShouldRefresh()
        }
    }
    @Published private(set) var timedServerModeSelectedDurationMinutes: Int? {
        didSet {
            if let timedServerModeSelectedDurationMinutes {
                defaults.set(timedServerModeSelectedDurationMinutes, forKey: DefaultsKey.timedServerModeSelectedDurationMinutes)
            } else {
                defaults.removeObject(forKey: DefaultsKey.timedServerModeSelectedDurationMinutes)
            }
            notifyMenuShouldRefresh()
        }
    }
    @Published private(set) var timedServerModeRemainingDisplay: String? {
        didSet {
            notifyMenuShouldRefresh()
        }
    }
    @Published private(set) var timedServerModeDurationOptions: [Int] {
        didSet {
            defaults.set(timedServerModeDurationOptions, forKey: AppDefaultsKey.timedServerModeDurationOptions)
            notifyMenuShouldRefresh()
        }
    }
    @Published private(set) var timedServerModePreventDisplaySleep: Bool {
        didSet {
            defaults.set(timedServerModePreventDisplaySleep, forKey: AppDefaultsKey.timedServerModePreventDisplaySleep)
            updateTimedDisplayAwakeAssertion()
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

    @Published private(set) var topMemoryApps: [MemoryUsageApp] = [] {
        didSet {
            notifyMenuShouldRefresh()
        }
    }
    @Published private(set) var systemPressure: SystemPressureSnapshot? {
        didSet {
            notifyMenuShouldRefresh()
        }
    }

    private let defaults: UserDefaults
    private let monitor: PowerSourceMonitor
    private let lidMonitor: LidStateMonitor
    private let powerManager: PowerManager
    private let memoryMonitor: MemoryUsageMonitor
    private let memoryHistoryStore: MemoryUsageHistoryStore
    private let launchAtLoginManager: LaunchAtLoginManager
    private let shouldStopExpiredTimedServerModeOnStart: Bool
    private var hasStarted = false
    private var wakeObserver: NSObjectProtocol?
    private var screensWakeObserver: NSObjectProtocol?
    private var didHandleBuiltInDisplayForClosedLid = false
    private var isBuiltInDisplayCommandRunning = false
    private var serverModeStartedAt: Date?
    private var runtimeTimer: Timer?
    private var timedServerModeTimer: Timer?
    private var isHandlingTimedServerModeExpiration = false
    private var batteryNotificationTimer: Timer?
    private var topMemoryAppsTimer: Timer?
    private var sentLowBatteryThresholds = Set<Int>()
    private var temporarilyAllowBatteryServerMode = false
    private var isRefreshingTopMemoryApps = false
    private var topMemoryAppsRefreshTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        monitor: PowerSourceMonitor = PowerSourceMonitor(),
        lidMonitor: LidStateMonitor = LidStateMonitor(),
        powerManager: PowerManager? = nil,
        memoryMonitor: MemoryUsageMonitor = MemoryUsageMonitor(),
        memoryHistoryStore: MemoryUsageHistoryStore = MemoryUsageHistoryStore(),
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager()
    ) {
        self.defaults = defaults
        self.monitor = monitor
        self.lidMonitor = lidMonitor
        self.powerManager = powerManager ?? PowerManager()
        self.memoryMonitor = memoryMonitor
        self.memoryHistoryStore = memoryHistoryStore
        self.launchAtLoginManager = launchAtLoginManager

        defaults.removeObject(forKey: "serverModeActive")
        defaults.removeObject(forKey: "savedPowerSettingsSnapshot")
        allowBatteryServerMode = defaults.bool(forKey: DefaultsKey.allowBatteryServerMode)
        let savedLowBatteryNotificationsEnabled = defaults.bool(forKey: AppDefaultsKey.lowBatteryNotificationsEnabled)
        let canEnableSavedLowBatteryNotifications = Self.canEnableLowBatteryNotifications(defaults: defaults)
        lowBatteryNotificationsEnabled = savedLowBatteryNotificationsEnabled && canEnableSavedLowBatteryNotifications
        hotKeysEnabled = defaults.object(forKey: AppDefaultsKey.hotKeysEnabled) as? Bool ?? true
        timedServerModePreventDisplaySleep = defaults.object(
            forKey: AppDefaultsKey.timedServerModePreventDisplaySleep
        ) as? Bool ?? false

        let savedServerModeRequested = defaults.bool(forKey: DefaultsKey.serverModeRequested)
        let savedTimedServerModeEndDate = defaults.object(forKey: DefaultsKey.timedServerModeEndDate) as? Date
        let savedTimedServerModeIsExpired = savedTimedServerModeEndDate.map { $0 <= Date() } ?? false
        shouldStopExpiredTimedServerModeOnStart = savedServerModeRequested && savedTimedServerModeIsExpired
        let effectiveServerModeRequested = savedServerModeRequested && !savedTimedServerModeIsExpired
        serverModeRequested = effectiveServerModeRequested

        let savedTimedServerModeDurationOptions = defaults.array(forKey: AppDefaultsKey.timedServerModeDurationOptions) as? [Int]
        let loadedTimedServerModeDurationOptions = Self.sanitizedTimedServerModeDurationOptions(
            savedTimedServerModeDurationOptions ?? Self.builtInTimedServerModeDurationOptions
        )
        timedServerModeDurationOptions = loadedTimedServerModeDurationOptions

        if let savedTimedServerModeEndDate,
           !savedTimedServerModeIsExpired,
           effectiveServerModeRequested {
            timedServerModeEndDate = savedTimedServerModeEndDate
            timedServerModeSelectedDurationMinutes = Self.normalizedTimedServerModeDuration(
                defaults.object(forKey: DefaultsKey.timedServerModeSelectedDurationMinutes) as? Int
            )
        } else {
            timedServerModeEndDate = nil
            timedServerModeSelectedDurationMinutes = nil
            defaults.removeObject(forKey: DefaultsKey.timedServerModeEndDate)
            defaults.removeObject(forKey: DefaultsKey.timedServerModeSelectedDurationMinutes)
            if savedTimedServerModeIsExpired {
                defaults.set(false, forKey: DefaultsKey.serverModeRequested)
            }
        }
        timedServerModeRemainingDisplay = nil

        let savedSource = defaults.string(forKey: DefaultsKey.lastKnownPowerSource)
        powerSource = savedSource.flatMap(PowerSource.init(rawValue:)) ?? .unknown
        lastCommandStatus = AppText.notStarted
        let savedServerModeStartedAt = defaults.object(forKey: DefaultsKey.serverModeStartedAt) as? Date
        let savedRuntimeHeartbeatAt = defaults.object(forKey: DefaultsKey.serverModeRuntimeHeartbeatAt) as? Date
        if Self.shouldKeepSavedServerModeRuntime(
            startedAt: savedServerModeStartedAt,
            heartbeatAt: savedRuntimeHeartbeatAt
        ) {
            serverModeStartedAt = savedServerModeStartedAt
        } else {
            serverModeStartedAt = nil
            defaults.removeObject(forKey: DefaultsKey.serverModeStartedAt)
            defaults.removeObject(forKey: DefaultsKey.serverModeRuntimeHeartbeatAt)
        }

        if savedLowBatteryNotificationsEnabled && !canEnableSavedLowBatteryNotifications {
            defaults.set(false, forKey: AppDefaultsKey.lowBatteryNotificationsEnabled)
        }

        refreshLaunchAtLoginEnabled()
        updateTimedServerModeRemainingDisplay()
        startTimedServerModeTimerIfNeeded()
    }

    var menuBarStatusTitle: String {
        if serverModeActive || (serverModeRequested && !isWaitingForPowerAdapter) {
            return isBatteryServerModeAllowedForCurrentSource
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
            return isBatteryServerModeAllowedForCurrentSource ? .serverModeBatteryAllowed : .serverModePowerOnly
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

    var hasTimedServerModeLimit: Bool {
        timedServerModeEndDate != nil
    }

    var canToggleTimedServerModePreventDisplaySleep: Bool {
        hasTimedServerModeLimit && !isCommandRunning
    }

    var timedServerModeDurationMenuOptions: [Int] {
        var durations = timedServerModeDurationOptions
        if let timedServerModeSelectedDurationMinutes,
           !durations.contains(timedServerModeSelectedDurationMinutes) {
            durations.append(timedServerModeSelectedDurationMinutes)
        }
        return Self.sanitizedTimedServerModeDurationOptions(durations)
    }

    var statusSummaryDisplay: String {
        guard serverModeRequested else {
            return AppText.notStarted
        }

        if powerSource == .batteryPower, !canRunServerMode(on: powerSource) {
            return AppText.connectPowerToKeepRunningWithLidClosed
        }

        return AppText.keepsRunningWithLidClosed
    }

    var serverModeTimeDisplay: String? {
        timedServerModeRemainingDisplay ?? serverModeRuntimeDisplay
    }

    var shouldShowMemoryUsageRows: Bool {
        serverModeRequested || serverModeActive
    }

    var systemPressureDisplay: String {
        guard let systemPressure else {
            return ""
        }

        return AppText.systemPressureSummary(
            memory: systemPressure.memoryDisplay,
            cpu: systemPressure.cpuPercentDisplay
        )
    }

    var systemPressureMemoryDisplay: String {
        systemPressure?.memoryDisplay ?? ""
    }

    var systemPressureCPUDisplay: String {
        systemPressure?.cpuPercentDisplay ?? ""
    }

    static func normalizedTimedServerModeDuration(_ minutes: Int?) -> Int? {
        guard let minutes,
              minutes >= minimumTimedServerModeDurationMinutes,
              minutes <= maximumTimedServerModeDurationMinutes else {
            return nil
        }

        return minutes
    }

    static func sanitizedTimedServerModeDurationOptions(_ durations: [Int]) -> [Int] {
        let validDurations = durations.compactMap { normalizedTimedServerModeDuration($0) }
        let uniqueDurations = Array(Set(validDurations)).sorted()
        return uniqueDurations.isEmpty ? builtInTimedServerModeDurationOptions : uniqueDurations
    }

    func startTimedServerMode(durationMinutes: Int) async {
        guard !isCommandRunning else {
            lastCommandStatus = AppText.commandAlreadyRunning
            return
        }

        guard let durationMinutes = Self.normalizedTimedServerModeDuration(durationMinutes) else {
            lastCommandStatus = AppText.invalidTimedServerModeDuration
            return
        }

        setTimedServerModeLimit(durationMinutes: durationMinutes)
        serverModeRequested = true
        await reconcileServerMode()

        if !serverModeRequested && !serverModeActive {
            clearTimedServerModeLimit()
        }
    }

    func setTimedServerModeDurationOptions(_ durations: [Int]) {
        let sanitizedDurations = Self.sanitizedTimedServerModeDurationOptions(durations)
        timedServerModeDurationOptions = sanitizedDurations
    }

    func addTimedServerModeDuration(minutes: Int) -> Int? {
        guard let minutes = Self.normalizedTimedServerModeDuration(minutes) else {
            lastCommandStatus = AppText.invalidTimedServerModeDuration
            return nil
        }

        setTimedServerModeDurationOptions(timedServerModeDurationOptions + [minutes])
        return minutes
    }

    func removeTimedServerModeDuration(minutes: Int) {
        guard timedServerModeDurationOptions.count > 1 else {
            return
        }

        let remainingDurations = timedServerModeDurationOptions.filter { $0 != minutes }
        setTimedServerModeDurationOptions(remainingDurations)
    }

    func resetTimedServerModeDurations() {
        timedServerModeDurationOptions = Self.builtInTimedServerModeDurationOptions
    }

    func clearTimedServerModeTimer() {
        guard hasTimedServerModeLimit else {
            return
        }

        clearTimedServerModeLimit()
        updateServerModeRuntimeDisplay()
        notifyMenuShouldRefresh()
    }

    func toggleTimedServerModePreventDisplaySleep() {
        guard canToggleTimedServerModePreventDisplaySleep else {
            return
        }

        timedServerModePreventDisplaySleep.toggle()
    }

    func setTimedServerModePreventDisplaySleep(_ isEnabled: Bool) {
        guard canToggleTimedServerModePreventDisplaySleep else {
            return
        }

        timedServerModePreventDisplaySleep = isEnabled
    }

    func handleDisplayConfigurationDidChange() {
        updateTimedDisplayAwakeAssertion()

        guard serverModeActive, lidState == .closed, !isCommandRunning else {
            return
        }

        Task {
            await dimClosedLidBuiltInDisplayIfNeeded(force: true)
        }
    }

    private func setTimedServerModeLimit(durationMinutes: Int) {
        let endDate = Date().addingTimeInterval(TimeInterval(durationMinutes * 60))
        timedServerModeSelectedDurationMinutes = durationMinutes
        timedServerModeEndDate = endDate
        updateTimedServerModeRemainingDisplay()
        startTimedServerModeTimerIfNeeded()
    }

    private func clearTimedServerModeLimit() {
        stopTimedServerModeTimer()
        timedServerModeEndDate = nil
        timedServerModeSelectedDurationMinutes = nil
        timedServerModeRemainingDisplay = nil
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
        recordServerModeRuntimeHeartbeat()
        updateServerModeRuntimeDisplay()
    }

    private func startServerModeRuntimeTimer() {
        guard runtimeTimer == nil else {
            return
        }

        runtimeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordServerModeRuntimeHeartbeat()
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
        defaults.removeObject(forKey: DefaultsKey.serverModeRuntimeHeartbeatAt)
    }

    private func recordServerModeRuntimeHeartbeat() {
        defaults.set(Date(), forKey: DefaultsKey.serverModeRuntimeHeartbeatAt)
    }

    private func updateServerModeRuntimeDisplay() {
        guard serverModeActive, let serverModeStartedAt else {
            serverModeRuntimeDisplay = nil
            return
        }

        let elapsedSeconds = max(0, Int(Date().timeIntervalSince(serverModeStartedAt)))
        serverModeRuntimeDisplay = AppText.serverModeRuntime(totalMinutes: elapsedSeconds / 60)
    }

    private static func shouldKeepSavedServerModeRuntime(startedAt: Date?, heartbeatAt: Date?) -> Bool {
        guard let startedAt else {
            return false
        }

        guard let heartbeatAt else {
            return false
        }

        let now = Date()
        guard startedAt <= now.addingTimeInterval(60) else {
            return false
        }

        return now.timeIntervalSince(heartbeatAt) <= maximumSavedRuntimeHeartbeatAge
    }

    private func startTimedServerModeTimerIfNeeded() {
        guard timedServerModeEndDate != nil, timedServerModeTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateTimedServerModeRemainingDisplay()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        timedServerModeTimer = timer
    }

    private func stopTimedServerModeTimer() {
        timedServerModeTimer?.invalidate()
        timedServerModeTimer = nil
    }

    private func updateTimedServerModeRemainingDisplay() {
        guard let timedServerModeEndDate else {
            timedServerModeRemainingDisplay = nil
            stopTimedServerModeTimer()
            return
        }

        let remainingSeconds = Int(ceil(timedServerModeEndDate.timeIntervalSinceNow))
        guard remainingSeconds > 0 else {
            timedServerModeRemainingDisplay = AppText.timedServerModeRemaining(totalSeconds: 0)
            handleTimedServerModeExpirationSoon()
            return
        }

        timedServerModeRemainingDisplay = AppText.timedServerModeRemaining(totalSeconds: remainingSeconds)
        startTimedServerModeTimerIfNeeded()
    }

    private func handleTimedServerModeExpirationSoon() {
        guard !isHandlingTimedServerModeExpiration else {
            return
        }

        isHandlingTimedServerModeExpiration = true
        Task { @MainActor [weak self] in
            await self?.handleTimedServerModeExpiration()
        }
    }

    private func handleTimedServerModeExpiration() async {
        defer {
            isHandlingTimedServerModeExpiration = false
        }

        guard timedServerModeEndDate != nil else {
            return
        }

        guard !isCommandRunning else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleTimedServerModeExpirationSoon()
                }
            }
            return
        }

        clearTimedServerModeLimit()

        if serverModeActive {
            await stopServerMode(clearRequest: true, successMessage: AppText.timedServerModeEnded)
        } else {
            setTemporaryBatteryServerModeAllowed(false)
            serverModeRequested = false
            lastCommandStatus = AppText.timedServerModeEnded
        }
    }

    private func stopExpiredTimedServerModeOnStartIfNeeded() async {
        guard shouldStopExpiredTimedServerModeOnStart else {
            return
        }

        clearTimedServerModeLimit()

        guard !isCommandRunning else {
            return
        }

        if serverModeActive {
            await stopServerMode(clearRequest: true, successMessage: AppText.timedServerModeEnded)
        } else {
            setTemporaryBatteryServerModeAllowed(false)
            serverModeRequested = false
            lastCommandStatus = AppText.timedServerModeEnded
        }
    }

    private var isWaitingForPowerAdapter: Bool {
        serverModeRequested && !serverModeActive && powerSource == .batteryPower && !canRunServerMode(on: powerSource)
    }

    private var isBatteryServerModeAllowedForCurrentSource: Bool {
        allowBatteryServerMode || (powerSource == .batteryPower && temporarilyAllowBatteryServerMode)
    }

    private func notifyStatusIconShouldRefresh() {
        NotificationCenter.default.post(name: .turnIntoServerStatusIconShouldRefresh, object: self)
        notifyMenuShouldRefresh()
    }

    private func notifyMenuShouldRefresh() {
        NotificationCenter.default.post(name: .turnIntoServerMenuShouldRefresh, object: self)
    }

    private func setTemporaryBatteryServerModeAllowed(_ isAllowed: Bool) {
        guard temporarilyAllowBatteryServerMode != isAllowed else {
            return
        }

        temporarilyAllowBatteryServerMode = isAllowed
        notifyStatusIconShouldRefresh()
        Task {
            await evaluateLowBatteryNotification()
        }
    }

    private func resetTemporaryBatteryServerModeAllowanceIfNeeded(for source: PowerSource? = nil) {
        guard temporarilyAllowBatteryServerMode else {
            return
        }

        let currentSource = source ?? powerSource
        if currentSource == .acPower || allowBatteryServerMode || !serverModeActive {
            setTemporaryBatteryServerModeAllowed(false)
        }
    }

    func start() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        startWakeObservers()
        startBatteryNotificationTimer()
        startTopMemoryAppsTimer()

        monitor.start { [weak self] source in
            self?.handlePowerSourceUpdate(source)
        }

        lidMonitor.start { [weak self] state in
            self?.handleLidStateUpdate(state)
        }

        Task {
            await refreshServerModeStatus()
            await stopExpiredTimedServerModeOnStartIfNeeded()
        }
    }

    private func startTopMemoryAppsTimer() {
        refreshTopMemoryApps()

        guard topMemoryAppsTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: Self.topMemoryAppsRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshTopMemoryApps()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        topMemoryAppsTimer = timer
    }

    private func refreshTopMemoryApps() {
        if isRefreshingTopMemoryApps {
            return
        }

        isRefreshingTopMemoryApps = true
        topMemoryAppsRefreshTask?.cancel()

        topMemoryAppsRefreshTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                self.isRefreshingTopMemoryApps = false
            }

            let snapshot = await self.memoryMonitor.currentSnapshot()
            guard !Task.isCancelled else {
                return
            }

            self.memoryHistoryStore.recordIfNeeded(snapshot: snapshot)
            self.systemPressure = snapshot.systemPressure
            self.topMemoryApps = self.memoryMonitor.topApplications(from: snapshot, limit: 5)
        }
    }

    func memoryUsageHistory(for app: MemoryUsageApp) -> MemoryUsageHistory? {
        memoryHistoryStore.history(
            for: app,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        )
    }

    func systemPressureHistory() -> SystemPressureHistory? {
        memoryHistoryStore.systemHistory(
            current: systemPressure,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        )
    }

    func setAllowBatteryServerMode(_ isEnabled: Bool) {
        guard allowBatteryServerMode != isEnabled else {
            return
        }

        setTemporaryBatteryServerModeAllowed(false)
        allowBatteryServerMode = isEnabled
        lastCommandStatus = isEnabled ? AppText.batteryPowerAllowed : AppText.batteryPowerRestricted

        Task {
            if serverModeRequested {
                await reconcileServerMode()
            }
            await evaluateLowBatteryNotification()
        }
    }

    func setServerModeEnabled(_ isEnabled: Bool) async {
        guard !isCommandRunning else {
            lastCommandStatus = AppText.commandAlreadyRunning
            return
        }

        if isEnabled {
            guard !serverModeRequested && !serverModeActive else {
                return
            }

            serverModeRequested = true
            await reconcileServerMode()
        } else {
            guard serverModeRequested || serverModeActive else {
                return
            }

            if await needsClosedLidStopConfirmation(),
               !confirmStopServerModeForClosedLidWithoutExternalDisplay() {
                lastCommandStatus = AppText.stopServerModeCancelled
                return
            }

            await disableServerMode()
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
        confirmClosedLidStop(
            title: AppText.stopServerModeConfirmationTitle,
            message: AppText.stopServerModeConfirmationMessage,
            continueTitle: AppText.stopServerModeConfirmationContinue
        )
    }

    private func confirmQuitForClosedLidWithoutExternalDisplay() -> Bool {
        confirmClosedLidStop(
            title: AppText.quitConfirmationTitle,
            message: AppText.quitConfirmationMessage,
            continueTitle: AppText.quitConfirmationContinue
        )
    }

    private func confirmBatteryRestrictionStopForClosedLidWithoutExternalDisplay() -> Bool {
        confirmClosedLidStop(
            title: AppText.batteryRestrictionConfirmationTitle,
            message: AppText.batteryRestrictionConfirmationMessage,
            continueTitle: AppText.batteryRestrictionConfirmationContinue
        )
    }

    private func confirmClosedLidStop(title: String, message: String, continueTitle: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: continueTitle)
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

    func setLowBatteryIMessageRecipientAddress(_ address: String) {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let verifiedAddress = defaults.string(forKey: AppDefaultsKey.verifiedIMessageRecipientAddress)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        defaults.set(address, forKey: AppDefaultsKey.iMessageRecipientAddress)
        if lowBatteryNotificationsEnabled && !Self.canEnableLowBatteryNotifications(defaults: defaults) {
            lowBatteryNotificationsEnabled = false
            sentLowBatteryThresholds.removeAll()
            lastCommandStatus = AppText.lowBatteryNotificationsRequireTest
        } else {
            lastCommandStatus = trimmedAddress.isEmpty || trimmedAddress == verifiedAddress
                ? AppText.lowBatteryNotificationSettingsUpdated
                : AppText.iMessageNeedsRetest
        }
    }

    func setLowBatteryBarkPushEndpoint(_ endpoint: String) {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let verifiedEndpoint = defaults.string(forKey: AppDefaultsKey.verifiedBarkPushEndpoint)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        defaults.set(endpoint, forKey: AppDefaultsKey.barkPushEndpoint)
        if lowBatteryNotificationsEnabled && !Self.canEnableLowBatteryNotifications(defaults: defaults) {
            lowBatteryNotificationsEnabled = false
            sentLowBatteryThresholds.removeAll()
            lastCommandStatus = AppText.lowBatteryNotificationsRequireTest
        } else {
            lastCommandStatus = trimmedEndpoint.isEmpty || trimmedEndpoint == verifiedEndpoint
                ? AppText.lowBatteryNotificationSettingsUpdated
                : AppText.barkNeedsRetest
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
        if await needsClosedLidStopConfirmation(),
           !confirmQuitForClosedLidWithoutExternalDisplay() {
            lastCommandStatus = AppText.quitCancelled
            return false
        }

        clearTimedServerModeLimit()
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
                if await needsClosedLidStopConfirmation(),
                   !confirmBatteryRestrictionStopForClosedLidWithoutExternalDisplay() {
                    setTemporaryBatteryServerModeAllowed(true)
                    lastCommandStatus = AppText.keptRunningOnBatteryForNow
                    await dimClosedLidBuiltInDisplayIfNeeded()
                    return
                }

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
            clearTimedServerModeLimit()
            setTemporaryBatteryServerModeAllowed(false)
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
        resetTemporaryBatteryServerModeAllowanceIfNeeded(for: detectedSource)
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
        resetTemporaryBatteryServerModeAllowanceIfNeeded(for: newSource)

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
        updateTimedDisplayAwakeAssertion()
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
              canRunServerMode(on: powerSource),
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

    private var shouldKeepDisplayAwakeForTimedServerMode: Bool {
        hasTimedServerModeLimit
            && timedServerModePreventDisplaySleep
            && !isClosedWithOnlyBuiltInDisplay
    }

    private var isClosedWithOnlyBuiltInDisplay: Bool {
        lidState == .closed && !BuiltInDisplayDimmer.hasOnlineExternalDisplay()
    }

    private func updateTimedDisplayAwakeAssertion() {
        let result = powerManager.setTimedDisplayAwakeEnabled(shouldKeepDisplayAwakeForTimedServerMode)
        if shouldKeepDisplayAwakeForTimedServerMode,
           case .failure(let message) = result {
            lastCommandStatus = AppText.failure(message)
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
            clearTimedServerModeLimit()
            serverModeRequested = false
            serverModeActive = false
            lastCommandStatus = AppText.userCancelledAuthorization
        case .failure(let message):
            clearTimedServerModeLimit()
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
            if clearRequest {
                clearTimedServerModeLimit()
            }
            setTemporaryBatteryServerModeAllowed(false)
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
        source != .batteryPower || allowBatteryServerMode || temporarilyAllowBatteryServerMode
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
