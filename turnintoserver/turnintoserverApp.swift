import AppKit
import Combine
import CoreText

@main
enum TurnIntoServerMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--mcp-server") {
            MCPStdioServer().run()
            return
        }

        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        withExtendedLifetime(appDelegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var hotKeyManager: HotKeyManager?
    private var statusItemController: StatusItemController?
    private var mcpControlServer: MCPControlServer?
    private var serverModeKeyEquivalentItem: NSMenuItem?
    private var batteryModeKeyEquivalentItem: NSMenuItem?
    private var hotKeysDidChangeObserver: NSObjectProtocol?
    private var isPreparingToTerminate = false
    private var didFinishTerminatePreparation = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureApplicationMenu()

        let state = AppState()
        appState = state
        hotKeyManager = HotKeyManager(
            onToggleServerMode: {
                await state.toggleServerMode()
            },
            onToggleBatteryServerMode: {
                state.toggleBatteryServerMode()
            }
        )
        hotKeyManager?.start()
        statusItemController = StatusItemController(appState: state)
        let controlServer = MCPControlServer(appState: state)
        mcpControlServer = controlServer
        controlServer.start()
        updateShortcutKeyEquivalentMenuItems()
        observeShortcutMenuItemChanges()
        state.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeysDidChangeObserver {
            NotificationCenter.default.removeObserver(hotKeysDidChangeObserver)
            self.hotKeysDidChangeObserver = nil
        }
        mcpControlServer?.stop()
        mcpControlServer = nil
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState else {
            return .terminateNow
        }

        if didFinishTerminatePreparation {
            return .terminateNow
        }

        guard !isPreparingToTerminate else {
            return .terminateLater
        }

        isPreparingToTerminate = true
        Task { @MainActor [weak self] in
            guard let self else {
                sender.reply(toApplicationShouldTerminate: false)
                return
            }

            let shouldTerminate = await appState.prepareForQuit()
            self.isPreparingToTerminate = false
            self.didFinishTerminatePreparation = shouldTerminate
            sender.reply(toApplicationShouldTerminate: shouldTerminate)
        }

        return .terminateLater
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        let serverModeKeyEquivalentItem = NSMenuItem(
            title: AppText.startServerMode,
            action: #selector(performServerModeKeyEquivalent(_:)),
            keyEquivalent: ""
        )
        serverModeKeyEquivalentItem.target = self
        appMenu.addItem(serverModeKeyEquivalentItem)
        self.serverModeKeyEquivalentItem = serverModeKeyEquivalentItem

        let batteryModeKeyEquivalentItem = NSMenuItem(
            title: AppText.allowBatteryServerMode,
            action: #selector(performBatteryModeKeyEquivalent(_:)),
            keyEquivalent: ""
        )
        batteryModeKeyEquivalentItem.target = self
        appMenu.addItem(batteryModeKeyEquivalentItem)
        self.batteryModeKeyEquivalentItem = batteryModeKeyEquivalentItem

        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(
                title: AppText.quit,
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: AppText.edit)
        editMenu.addItem(NSMenuItem(title: AppText.cut, action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: AppText.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: AppText.paste, action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(.separator())
        editMenu.addItem(
            NSMenuItem(
                title: AppText.selectAll,
                action: #selector(NSStandardKeyBindingResponding.selectAll(_:)),
                keyEquivalent: "a"
            )
        )
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func observeShortcutMenuItemChanges() {
        guard hotKeysDidChangeObserver == nil else {
            return
        }

        hotKeysDidChangeObserver = NotificationCenter.default.addObserver(
            forName: .turnIntoServerHotKeysDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateShortcutKeyEquivalentMenuItems()
            }
        }
    }

    private func updateShortcutKeyEquivalentMenuItems() {
        let hotKeysEnabled = appState?.hotKeysEnabled ?? true
        configureKeyEquivalentMenuItem(
            serverModeKeyEquivalentItem,
            shortcut: hotKeysEnabled ? serverModeShortcut : nil
        )
        configureKeyEquivalentMenuItem(
            batteryModeKeyEquivalentItem,
            shortcut: hotKeysEnabled ? batteryModeShortcut : nil
        )
    }

    private var serverModeShortcut: HotKeyShortcut? {
        HotKeyShortcut.loadOptional(
            defaultsKey: AppDefaultsKey.serverModeHotKey,
            disabledDefaultsKey: AppDefaultsKey.serverModeHotKeyDisabled,
            default: .defaultServerMode
        )
    }

    private var batteryModeShortcut: HotKeyShortcut? {
        HotKeyShortcut.loadOptional(
            defaultsKey: AppDefaultsKey.batteryModeHotKey,
            disabledDefaultsKey: AppDefaultsKey.batteryModeHotKeyDisabled,
            default: .defaultBatteryMode
        )
    }

    private func configureKeyEquivalentMenuItem(_ item: NSMenuItem?, shortcut: HotKeyShortcut?) {
        guard let item else {
            return
        }

        guard let shortcut, let keyEquivalent = shortcut.keyEquivalent else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            return
        }

        item.keyEquivalent = keyEquivalent
        item.keyEquivalentModifierMask = shortcut.keyEquivalentModifierMask
    }

    @objc private func performServerModeKeyEquivalent(_ sender: Any?) {
        guard let appState else {
            return
        }

        statusItemController?.cancelMenuTrackingForKeyEquivalent()
        Task { @MainActor in
            await appState.toggleServerMode()
        }
    }

    @objc private func performBatteryModeKeyEquivalent(_ sender: Any?) {
        guard let appState else {
            return
        }

        statusItemController?.cancelMenuTrackingForKeyEquivalent()
        appState.toggleBatteryServerMode()
    }
}

@MainActor
private final class StatusItemController: NSObject, NSMenuDelegate {
    private enum MenuShortcutAction {
        case serverMode
        case batteryMode
    }

    private let appState: AppState
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var aboutWindowController: AboutWindowController?
    private var timedServerModeSettingsWindowController: TimedServerModeSettingsWindowController?
    private var lowBatterySettingsWindowController: LowBatterySettingsWindowController?
    private var shortcutSettingsWindowController: ShortcutSettingsWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var isMenuOpen = false
    private var menuShortcutEventMonitor: Any?
    private var lastHandledMenuShortcutEventTimestamp: TimeInterval?
    private weak var serverModeRowView: MenuActionRowView?
    private weak var statusSummaryRowView: MenuTextRowView?
    private weak var runtimeRowView: MenuTextRowView?
    private weak var timedServerModeMenuItem: NSMenuItem?
    private weak var timedServerModeRowView: MenuSubmenuRowView?
    private var timedDurationRowViews: [Int: MenuStateActionRowView] = [:]
    private weak var timedPreventDisplaySleepRowView: MenuStateActionRowView?
    private var timedSubmenuDurationOptions: [Int] = []
    private weak var memorySectionHeaderRowView: MenuMemorySectionHeaderRowView?
    private var topMemoryAppRowViews: [MenuMemoryAppRowView] = []
    private let memoryTrendPanelController = MemoryTrendPanelController()
    private var memorySectionExpanded = false
    private var lastServerModeMemoryDefaultExpanded = false
    private weak var batteryRowView: MenuToggleRowView?
    private weak var lowBatteryRowView: MenuToggleRowView?
    private weak var shortcutsRowView: MenuToggleRowView?
    private weak var launchAtLoginRowView: MenuToggleRowView?
    private weak var quitMenuItem: NSMenuItem?

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        memorySectionExpanded = appState.shouldShowMemoryUsageRows
        lastServerModeMemoryDefaultExpanded = appState.shouldShowMemoryUsageRows
        configureStatusItem()
        observeAppState()
        updateStatusButton()
        rebuildMenu()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureStatusItem() {
        menu.delegate = self
        statusItem.menu = menu

        guard let button = statusItem.button else {
            return
        }

        button.imagePosition = .imageLeading
        button.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        button.toolTip = appState.menuBarStatusTitle
    }

    private func observeAppState() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(statusIconShouldRefresh(_:)),
            name: .turnIntoServerStatusIconShouldRefresh,
            object: appState
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuShouldRefresh(_:)),
            name: .turnIntoServerMenuShouldRefresh,
            object: appState
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayMetricsDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayMetricsDidChange(_:)),
            name: NSWindow.didChangeBackingPropertiesNotification,
            object: nil
        )

        Publishers.CombineLatest4(
            appState.$serverModeActive,
            appState.$serverModeRequested,
            appState.$allowBatteryServerMode,
            appState.$powerSource
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.updateStatusButton()
        }
        .store(in: &cancellables)

        let menuRefreshPublishers: [AnyPublisher<Void, Never>] = [
            appState.$serverModeActive.map { _ in () }.eraseToAnyPublisher(),
            appState.$serverModeRequested.map { _ in () }.eraseToAnyPublisher(),
            appState.$allowBatteryServerMode.map { _ in () }.eraseToAnyPublisher(),
            appState.$lowBatteryNotificationsEnabled.map { _ in () }.eraseToAnyPublisher(),
            appState.$hotKeysEnabled.map { _ in () }.eraseToAnyPublisher(),
            appState.$launchAtLoginEnabled.map { _ in () }.eraseToAnyPublisher(),
            appState.$isLaunchAtLoginChanging.map { _ in () }.eraseToAnyPublisher(),
            appState.$isCommandRunning.map { _ in () }.eraseToAnyPublisher(),
            appState.$serverModeRuntimeDisplay.map { _ in () }.eraseToAnyPublisher(),
            appState.$timedServerModeEndDate.map { _ in () }.eraseToAnyPublisher(),
            appState.$timedServerModeSelectedDurationMinutes.map { _ in () }.eraseToAnyPublisher(),
            appState.$timedServerModeRemainingDisplay.map { _ in () }.eraseToAnyPublisher(),
            appState.$timedServerModeDurationOptions.map { _ in () }.eraseToAnyPublisher(),
            appState.$timedServerModePreventDisplaySleep.map { _ in () }.eraseToAnyPublisher(),
            appState.$topMemoryApps.map { _ in () }.eraseToAnyPublisher(),
            appState.$powerSource.map { _ in () }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(menuRefreshPublishers)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshMenuIfOpen()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .turnIntoServerHotKeysDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshMenuIfOpen()
            }
            .store(in: &cancellables)
    }

    @objc private func statusIconShouldRefresh(_ notification: Notification) {
        updateStatusButton()
    }

    @objc private func menuShouldRefresh(_ notification: Notification) {
        updateStatusButton()
        refreshMenuAfterStateChange()
    }

    @objc private func displayMetricsDidChange(_ notification: Notification) {
        if notification.name == NSWindow.didChangeBackingPropertiesNotification,
           let changedWindow = notification.object as? NSWindow,
           changedWindow !== statusItem.button?.window {
            return
        }

        appState.handleDisplayConfigurationDidChange()
        refreshStatusAndMenuForCurrentDisplay()

        DispatchQueue.main.async { [weak self] in
            self?.refreshStatusAndMenuForCurrentDisplay()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refreshStatusAndMenuForCurrentDisplay()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        lastHandledMenuShortcutEventTimestamp = nil
        installMenuShortcutEventMonitor()
        NotificationCenter.default.post(name: .turnIntoServerMenuHotKeyCaptureDidStart, object: nil)
        appState.refreshLaunchAtLoginStatus()
        resetMemorySectionExpansionForMenuOpen()
        rebuildMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        memoryTrendPanelController.hide()
        removeMenuShortcutEventMonitor()
        NotificationCenter.default.post(name: .turnIntoServerMenuHotKeyCaptureDidEnd, object: nil)
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard let event = NSApp.currentEvent,
              event.type == .keyDown,
              !event.isARepeat,
              let action = Self.menuShortcutAction(for: event) else {
            return
        }

        performMenuShortcutAction(action, eventTimestamp: event.timestamp)
    }

    func cancelMenuTrackingForKeyEquivalent() {
        menu.cancelTracking()
    }

    @objc private func performServerModeMenuKeyEquivalent(_ sender: Any?) {
        menu.cancelTracking()
        Task { @MainActor in
            await appState.toggleServerMode()
            updateStatusButton()
        }
    }

    @objc private func performBatteryModeMenuKeyEquivalent(_ sender: Any?) {
        menu.cancelTracking()
        appState.toggleBatteryServerMode()
        updateStatusButton()
    }

    private func installMenuShortcutEventMonitor() {
        removeMenuShortcutEventMonitor()

        menuShortcutEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard !event.isARepeat,
                  let action = Self.menuShortcutAction(for: event) else {
                return event
            }

            let eventTimestamp = event.timestamp
            Task { @MainActor [weak self] in
                self?.performMenuShortcutAction(action, eventTimestamp: eventTimestamp)
            }
            return nil
        }
    }

    private func removeMenuShortcutEventMonitor() {
        if let menuShortcutEventMonitor {
            NSEvent.removeMonitor(menuShortcutEventMonitor)
            self.menuShortcutEventMonitor = nil
        }
    }

    private nonisolated static func menuShortcutAction(for event: NSEvent) -> MenuShortcutAction? {
        guard UserDefaults.standard.object(forKey: AppDefaultsKey.hotKeysEnabled) as? Bool ?? true else {
            return nil
        }

        if let shortcut = HotKeyShortcut.loadOptional(
            defaultsKey: AppDefaultsKey.serverModeHotKey,
            disabledDefaultsKey: AppDefaultsKey.serverModeHotKeyDisabled,
            default: .defaultServerMode
        ), shortcut.matches(event: event) {
            return .serverMode
        }

        if let shortcut = HotKeyShortcut.loadOptional(
            defaultsKey: AppDefaultsKey.batteryModeHotKey,
            disabledDefaultsKey: AppDefaultsKey.batteryModeHotKeyDisabled,
            default: .defaultBatteryMode
        ), shortcut.matches(event: event) {
            return .batteryMode
        }

        return nil
    }

    private func performMenuShortcutAction(
        _ action: MenuShortcutAction,
        eventTimestamp: TimeInterval? = nil
    ) {
        if let eventTimestamp {
            if let lastHandledMenuShortcutEventTimestamp,
               (lastHandledMenuShortcutEventTimestamp - eventTimestamp).magnitude < 0.001 {
                return
            }

            lastHandledMenuShortcutEventTimestamp = eventTimestamp
        }

        menu.cancelTracking()

        switch action {
        case .serverMode:
            Task { @MainActor in
                await appState.toggleServerMode()
                updateStatusButton()
            }
        case .batteryMode:
            appState.toggleBatteryServerMode()
            updateStatusButton()
        }
    }

    private func rebuildMenu() {
        memoryTrendPanelController.hide()
        menu.removeAllItems()
        serverModeRowView = nil
        statusSummaryRowView = nil
        runtimeRowView = nil
        timedServerModeMenuItem = nil
        timedServerModeRowView = nil
        timedDurationRowViews = [:]
        timedPreventDisplaySleepRowView = nil
        timedSubmenuDurationOptions = []
        memorySectionHeaderRowView = nil
        topMemoryAppRowViews = []
        batteryRowView = nil
        lowBatteryRowView = nil
        shortcutsRowView = nil
        launchAtLoginRowView = nil
        quitMenuItem = nil

        addHiddenShortcutMenuItems()

        let serverModeItem = NSMenuItem()
        let serverModeView = MenuActionRowView(
            title: appState.serverModeActionTitle,
            image: MenuBarStatusIconRenderer.menuServerModeImage(
                for: appState.menuBarIconStyle,
                fallbackSystemName: appState.serverModeActionSystemImage
            ),
            shortcutTitle: serverModeShortcutDisplay,
            isEnabled: !appState.isCommandRunning,
            target: self,
            action: #selector(toggleServerMode(_:)),
            width: MenuRowMetric.width,
            height: MenuRowMetric.height
        )
        serverModeItem.view = serverModeView
        serverModeRowView = serverModeView
        menu.addItem(serverModeItem)

        let statusItem = NSMenuItem()
        let statusSummaryView = MenuTextRowView(title: appState.statusSummaryDisplay)
        statusItem.view = statusSummaryView
        statusSummaryRowView = statusSummaryView
        menu.addItem(statusItem)

        if let runtimeDisplay = appState.serverModeTimeDisplay {
            let runtimeItem = NSMenuItem()
            let runtimeView = MenuTextRowView(title: runtimeDisplay)
            runtimeItem.view = runtimeView
            runtimeRowView = runtimeView
            menu.addItem(runtimeItem)
        }

        menu.addItem(.separator())

        let timedServerModeItem = NSMenuItem()
        let timedServerModeView = MenuSubmenuRowView(
            title: AppText.timedServerMode,
            isOn: appState.hasTimedServerModeLimit,
            isEnabled: !appState.isCommandRunning
        )
        timedServerModeItem.view = timedServerModeView
        timedServerModeMenuItem = timedServerModeItem
        timedServerModeRowView = timedServerModeView
        configureTimedServerModeMenuItem(timedServerModeItem)
        menu.addItem(timedServerModeItem)

        menu.addItem(.separator())

        addTopMemoryAppsSection()
        menu.addItem(.separator())

        let batteryItem = NSMenuItem()
        let batteryView = MenuToggleRowView(
            title: AppText.allowBatteryServerMode,
            isOn: appState.allowBatteryServerMode,
            isToggleEnabled: !appState.isCommandRunning,
            shortcutTitle: batteryModeShortcutDisplay,
            target: self,
            toggleAction: #selector(toggleBatteryServerMode(_:))
        )
        batteryItem.view = batteryView
        batteryRowView = batteryView
        menu.addItem(batteryItem)

        let lowBatteryItem = NSMenuItem()
        let lowBatteryView = MenuToggleRowView(
            title: AppText.lowBatteryNotifications,
            isOn: appState.lowBatteryNotificationsEnabled,
            isToggleEnabled: appState.lowBatteryNotificationsEnabled
                || AppState.canEnableLowBatteryNotifications(),
            settingsButtonTitle: AppText.configureLowBatteryNotifications,
            target: self,
            toggleAction: #selector(toggleLowBatteryNotifications(_:)),
            settingsAction: #selector(showLowBatterySettings(_:))
        )
        lowBatteryItem.view = lowBatteryView
        lowBatteryRowView = lowBatteryView
        menu.addItem(lowBatteryItem)

        let shortcutsItem = NSMenuItem()
        let shortcutsView = MenuToggleRowView(
            title: AppText.enableShortcuts,
            isOn: appState.hotKeysEnabled,
            isToggleEnabled: true,
            settingsButtonTitle: AppText.configureShortcuts,
            target: self,
            toggleAction: #selector(toggleHotKeys(_:)),
            settingsAction: #selector(showShortcutSettings(_:))
        )
        shortcutsItem.view = shortcutsView
        shortcutsRowView = shortcutsView
        menu.addItem(shortcutsItem)

        let launchAtLoginItem = NSMenuItem()
        let launchAtLoginView = MenuToggleRowView(
            title: AppText.launchAtLogin,
            isOn: appState.launchAtLoginEnabled,
            isToggleEnabled: appState.launchAtLoginSupported && !appState.isLaunchAtLoginChanging,
            tooltip: appState.launchAtLoginSupported ? nil : AppText.launchAtLoginUnsupported,
            target: self,
            toggleAction: #selector(toggleLaunchAtLogin(_:))
        )
        launchAtLoginItem.view = launchAtLoginView
        launchAtLoginRowView = launchAtLoginView
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: AppText.aboutApplication, action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: AppText.quit, action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        quitItem.isEnabled = !appState.isCommandRunning
        quitMenuItem = quitItem
        menu.addItem(quitItem)
    }

    private func addTopMemoryAppsSection() {
        let isExpanded = memorySectionExpanded

        let headerItem = NSMenuItem()
        let headerView = MenuMemorySectionHeaderRowView(
            title: AppText.memoryUsageSectionTitle,
            memoryDetail: appState.systemPressureMemoryDisplay,
            cpuDetail: appState.systemPressureCPUDisplay,
            isExpanded: isExpanded,
            target: self,
            action: #selector(toggleMemorySectionExpansion(_:)),
            onHoverBegan: { [weak self] anchorView in
                self?.showSystemPressureTrend(relativeTo: anchorView)
            },
            onHoverEnded: { [weak self] in
                self?.hideSystemPressureTrendIfNeeded()
            }
        )
        headerItem.view = headerView
        memorySectionHeaderRowView = headerView
        menu.addItem(headerItem)

        guard isExpanded else {
            return
        }

        let apps = appState.topMemoryApps
        guard !apps.isEmpty else {
            return
        }

        for app in apps {
            let appItem = NSMenuItem()
            let appView = MenuMemoryAppRowView(
                app: app,
                onHoverBegan: { [weak self] app, anchorView in
                    self?.showMemoryTrend(for: app, relativeTo: anchorView)
                },
                onHoverEnded: { [weak self] app in
                    self?.hideMemoryTrendIfNeeded(for: app)
                }
            )
            appItem.view = appView
            topMemoryAppRowViews.append(appView)
            menu.addItem(appItem)
        }
    }

    @objc private func toggleMemorySectionExpansion(_ sender: Any?) {
        memorySectionExpanded.toggle()
        if !memorySectionExpanded {
            memoryTrendPanelController.hide()
        }
        refreshMenuAfterStateChange()
    }

    private func showSystemPressureTrend(relativeTo anchorView: NSView) {
        guard let history = appState.systemPressureHistory() else {
            memoryTrendPanelController.hide()
            return
        }

        memoryTrendPanelController.show(systemHistory: history, relativeTo: anchorView)
    }

    private func hideSystemPressureTrendIfNeeded() {
        guard memoryTrendPanelController.visibleAppID == SystemPressureHistory.id else {
            return
        }

        memoryTrendPanelController.hide()
    }

    private func showMemoryTrend(for app: MemoryUsageApp, relativeTo anchorView: NSView) {
        guard let history = appState.memoryUsageHistory(for: app) else {
            memoryTrendPanelController.hide()
            return
        }

        memoryTrendPanelController.show(history: history, relativeTo: anchorView)
    }

    private func hideMemoryTrendIfNeeded(for app: MemoryUsageApp) {
        guard memoryTrendPanelController.visibleAppID == app.id else {
            return
        }

        memoryTrendPanelController.hide()
    }

    private func addHiddenShortcutMenuItems() {
        let serverModeItem = hiddenShortcutMenuItem(
            shortcut: appState.hotKeysEnabled ? serverModeShortcut : nil,
            action: #selector(performServerModeMenuKeyEquivalent(_:))
        )
        menu.addItem(serverModeItem)

        let batteryModeItem = hiddenShortcutMenuItem(
            shortcut: appState.hotKeysEnabled ? batteryModeShortcut : nil,
            action: #selector(performBatteryModeMenuKeyEquivalent(_:))
        )
        menu.addItem(batteryModeItem)
    }

    private func hiddenShortcutMenuItem(shortcut: HotKeyShortcut?, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
        item.target = self
        item.isHidden = true

        guard let shortcut, let keyEquivalent = shortcut.keyEquivalent else {
            return item
        }

        item.keyEquivalent = keyEquivalent
        item.keyEquivalentModifierMask = shortcut.keyEquivalentModifierMask
        return item
    }

    private func configureTimedServerModeMenuItem(_ item: NSMenuItem) {
        item.title = ""
        item.state = .off
        item.isEnabled = !appState.isCommandRunning
        let durationOptions = appState.timedServerModeDurationMenuOptions
        timedServerModeRowView?.update(
            title: AppText.timedServerMode,
            isOn: appState.hasTimedServerModeLimit,
            isEnabled: !appState.isCommandRunning
        )

        if item.submenu == nil || timedSubmenuDurationOptions != durationOptions {
            item.submenu = buildTimedServerModeSubmenu(durationOptions: durationOptions)
        } else {
            updateTimedServerModeSubmenuRows()
        }
    }

    private func buildTimedServerModeSubmenu(durationOptions: [Int]) -> NSMenu {
        let submenu = NSMenu()
        timedDurationRowViews = [:]
        timedSubmenuDurationOptions = durationOptions

        for durationMinutes in durationOptions {
            let durationItem = makeTimedSubmenuActionItem(
                title: AppText.timedServerModeDuration(minutes: durationMinutes),
                state: appState.hasTimedServerModeLimit
                    && appState.timedServerModeSelectedDurationMinutes == durationMinutes ? .on : .off,
                isEnabled: !appState.isCommandRunning,
                action: #selector(selectTimedServerModeDuration(_:)),
                representedObject: durationMinutes
            )
            timedDurationRowViews[durationMinutes] = durationItem.view as? MenuStateActionRowView
            submenu.addItem(durationItem)
        }

        submenu.addItem(.separator())

        let preventDisplaySleepItem = makeTimedSubmenuActionItem(
            title: AppText.preventTimedServerModeDisplaySleep,
            state: timedPreventDisplaySleepState,
            isEnabled: appState.canToggleTimedServerModePreventDisplaySleep,
            action: #selector(toggleTimedServerModePreventDisplaySleep(_:)),
            representedObject: nil
        )
        timedPreventDisplaySleepRowView = preventDisplaySleepItem.view as? MenuStateActionRowView
        submenu.addItem(preventDisplaySleepItem)

        let settingsItem = NSMenuItem(
            title: AppText.timedServerModeSettings,
            action: #selector(showTimedServerModeSettings(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = self
        submenu.addItem(settingsItem)

        return submenu
    }

    private var timedPreventDisplaySleepState: MenuItemState {
        guard appState.timedServerModePreventDisplaySleep else {
            return .off
        }

        return appState.hasTimedServerModeLimit ? .on : .mixed
    }

    private func makeTimedSubmenuActionItem(
        title: String,
        state: MenuItemState,
        isEnabled: Bool,
        action: Selector,
        representedObject: Any?
    ) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuStateActionRowView(
            title: title,
            state: state,
            isEnabled: isEnabled,
            target: self,
            action: action,
            representedObject: representedObject,
            width: MenuRowMetric.submenuWidth
        )
        return item
    }

    private func updateTimedServerModeSubmenuRows() {
        for durationMinutes in timedSubmenuDurationOptions {
            timedDurationRowViews[durationMinutes]?.update(
                title: AppText.timedServerModeDuration(minutes: durationMinutes),
                state: appState.hasTimedServerModeLimit
                    && appState.timedServerModeSelectedDurationMinutes == durationMinutes ? .on : .off,
                isEnabled: !appState.isCommandRunning
            )
        }

        timedPreventDisplaySleepRowView?.update(
            title: AppText.preventTimedServerModeDisplaySleep,
            state: timedPreventDisplaySleepState,
            isEnabled: appState.canToggleTimedServerModePreventDisplaySleep
        )
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        let style = appState.menuBarIconStyle
        button.image = MenuBarStatusIconRenderer.image(for: style)
        button.title = MenuBarStatusIconRenderer.title(for: style)
        button.toolTip = appState.menuBarStatusTitle
        button.needsLayout = true
        button.needsDisplay = true
        button.displayIfNeeded()
        button.window?.displayIfNeeded()
    }

    private func refreshMenuIfOpen() {
        guard isMenuOpen else {
            syncMemorySectionExpansionWithServerMode()
            return
        }

        syncMemorySectionExpansionWithServerMode()
        updateVisibleMenuRowsOrRebuild()
    }

    private func refreshStatusAndMenuForCurrentDisplay() {
        updateStatusButton()
        refreshMenuIfOpen()
    }

    private func updateVisibleMenuRowsOrRebuild() {
        let runtimeShouldBeVisible = appState.serverModeTimeDisplay != nil
        let runtimeIsVisible = runtimeRowView != nil
        let memoryHeaderShouldBeVisible = true
        let memoryHeaderIsVisible = memorySectionHeaderRowView != nil
        let visibleMemoryApps = memorySectionExpanded ? appState.topMemoryApps : []

        guard runtimeShouldBeVisible == runtimeIsVisible,
              memoryHeaderShouldBeVisible == memoryHeaderIsVisible,
              topMemoryAppRowViews.count == visibleMemoryApps.count,
              let serverModeRowView,
              let statusSummaryRowView,
              let timedServerModeMenuItem,
              let timedServerModeRowView,
              let batteryRowView,
              let lowBatteryRowView,
              let shortcutsRowView,
              let launchAtLoginRowView else {
            rebuildMenu()
            return
        }

        serverModeRowView.update(
            title: appState.serverModeActionTitle,
            image: MenuBarStatusIconRenderer.menuServerModeImage(
                for: appState.menuBarIconStyle,
                fallbackSystemName: appState.serverModeActionSystemImage
            ),
            shortcutTitle: serverModeShortcutDisplay,
            isEnabled: !appState.isCommandRunning
        )
        statusSummaryRowView.update(title: appState.statusSummaryDisplay)
        runtimeRowView?.update(title: appState.serverModeTimeDisplay ?? "")
        memorySectionHeaderRowView?.update(
            title: AppText.memoryUsageSectionTitle,
            memoryDetail: appState.systemPressureMemoryDisplay,
            cpuDetail: appState.systemPressureCPUDisplay,
            isExpanded: memorySectionExpanded
        )
        zip(topMemoryAppRowViews, visibleMemoryApps).forEach { rowView, app in
            rowView.update(app: app)
        }
        refreshMemoryTrendPanelIfNeeded(visibleMemoryApps: visibleMemoryApps)
        configureTimedServerModeMenuItem(timedServerModeMenuItem)
        batteryRowView.update(
            title: AppText.allowBatteryServerMode,
            isOn: appState.allowBatteryServerMode,
            isToggleEnabled: !appState.isCommandRunning,
            shortcutTitle: batteryModeShortcutDisplay
        )
        lowBatteryRowView.update(
            title: AppText.lowBatteryNotifications,
            isOn: appState.lowBatteryNotificationsEnabled,
            isToggleEnabled: appState.lowBatteryNotificationsEnabled
                || AppState.canEnableLowBatteryNotifications()
        )
        shortcutsRowView.update(
            title: AppText.enableShortcuts,
            isOn: appState.hotKeysEnabled,
            isToggleEnabled: true
        )
        launchAtLoginRowView.update(
            title: AppText.launchAtLogin,
            isOn: appState.launchAtLoginEnabled,
            isToggleEnabled: appState.launchAtLoginSupported && !appState.isLaunchAtLoginChanging,
            tooltip: appState.launchAtLoginSupported ? nil : AppText.launchAtLoginUnsupported
        )
        quitMenuItem?.isEnabled = !appState.isCommandRunning

        let visibleRowViews = [
            serverModeRowView,
            statusSummaryRowView,
            runtimeRowView,
            memorySectionHeaderRowView,
            timedServerModeRowView,
            batteryRowView,
            lowBatteryRowView,
            shortcutsRowView,
            launchAtLoginRowView
        ]

        let visibleTimedSubmenuRowViews: [NSView] = [
            timedPreventDisplaySleepRowView
        ]
        .compactMap { $0 } + Array(timedDurationRowViews.values)

        (visibleRowViews.compactMap { $0 } + topMemoryAppRowViews + visibleTimedSubmenuRowViews).forEach { view in
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            view.window?.displayIfNeeded()
        }
        menu.update()
    }

    private func refreshMemoryTrendPanelIfNeeded(visibleMemoryApps: [MemoryUsageApp]) {
        guard let visibleAppID = memoryTrendPanelController.visibleAppID else {
            return
        }

        if visibleAppID == SystemPressureHistory.id {
            guard let history = appState.systemPressureHistory() else {
                memoryTrendPanelController.hide()
                return
            }

            memoryTrendPanelController.update(systemHistory: history)
            return
        }

        guard let visibleApp = visibleMemoryApps.first(where: { $0.id == visibleAppID }),
              let history = appState.memoryUsageHistory(for: visibleApp) else {
            memoryTrendPanelController.hide()
            return
        }

        memoryTrendPanelController.update(history: history)
    }

    private func resetMemorySectionExpansionForMenuOpen() {
        memorySectionExpanded = appState.shouldShowMemoryUsageRows
        lastServerModeMemoryDefaultExpanded = appState.shouldShowMemoryUsageRows
    }

    private func syncMemorySectionExpansionWithServerMode() {
        let shouldDefaultExpand = appState.shouldShowMemoryUsageRows
        if shouldDefaultExpand != lastServerModeMemoryDefaultExpanded {
            memorySectionExpanded = shouldDefaultExpand
            if !memorySectionExpanded {
                memoryTrendPanelController.hide()
            }
            lastServerModeMemoryDefaultExpanded = shouldDefaultExpand
        } else if !memorySectionExpanded,
                  memoryTrendPanelController.visibleAppID != SystemPressureHistory.id {
            memoryTrendPanelController.hide()
        }
    }

    private func refreshMenuSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshMenuIfOpen()
        }
    }

    private func refreshMenuAfterStateChange() {
        if isHandlingMenuMouseEvent {
            refreshMenuSoon()
        } else {
            refreshMenuIfOpen()
        }
    }

    private var isHandlingMenuMouseEvent: Bool {
        switch NSApp.currentEvent?.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            return true
        default:
            return false
        }
    }

    private var serverModeShortcutDisplay: String? {
        HotKeyShortcut.loadOptional(
            defaultsKey: AppDefaultsKey.serverModeHotKey,
            disabledDefaultsKey: AppDefaultsKey.serverModeHotKeyDisabled,
            default: .defaultServerMode
        )?.menuDisplayString
    }

    private var batteryModeShortcutDisplay: String? {
        HotKeyShortcut.loadOptional(
            defaultsKey: AppDefaultsKey.batteryModeHotKey,
            disabledDefaultsKey: AppDefaultsKey.batteryModeHotKeyDisabled,
            default: .defaultBatteryMode
        )?.menuDisplayString
    }

    private var serverModeShortcut: HotKeyShortcut? {
        HotKeyShortcut.loadOptional(
            defaultsKey: AppDefaultsKey.serverModeHotKey,
            disabledDefaultsKey: AppDefaultsKey.serverModeHotKeyDisabled,
            default: .defaultServerMode
        )
    }

    private var batteryModeShortcut: HotKeyShortcut? {
        HotKeyShortcut.loadOptional(
            defaultsKey: AppDefaultsKey.batteryModeHotKey,
            disabledDefaultsKey: AppDefaultsKey.batteryModeHotKeyDisabled,
            default: .defaultBatteryMode
        )
    }

    @objc private func toggleServerMode(_ sender: Any?) {
        Task { @MainActor in
            await appState.toggleServerMode()
            updateStatusButton()
            refreshMenuSoon()
        }
    }

    @objc private func toggleBatteryServerMode(_ sender: Any?) {
        appState.toggleBatteryServerMode()
        updateStatusButton()
        refreshMenuSoon()
    }

    @objc private func toggleLowBatteryNotifications(_ sender: Any?) {
        appState.toggleLowBatteryNotifications()
        refreshMenuSoon()
    }

    @objc private func toggleHotKeys(_ sender: Any?) {
        appState.toggleHotKeysEnabled()
        refreshMenuSoon()
    }

    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        appState.setLaunchAtLoginEnabled(!appState.launchAtLoginEnabled)
        refreshMenuSoon()
    }

    @objc private func toggleTimedServerModePreventDisplaySleep(_ sender: Any?) {
        appState.toggleTimedServerModePreventDisplaySleep()
        refreshMenuSoon()
    }

    @objc private func selectTimedServerModeDuration(_ sender: Any?) {
        let durationMinutes: Int?
        if let button = sender as? MenuRowButton,
           let number = button.representedObject as? NSNumber {
            durationMinutes = number.intValue
        } else if let button = sender as? MenuRowButton,
                  let value = button.representedObject as? Int {
            durationMinutes = value
        } else if let item = sender as? NSMenuItem,
                  let number = item.representedObject as? NSNumber {
            durationMinutes = number.intValue
        } else if let item = sender as? NSMenuItem {
            durationMinutes = item.representedObject as? Int
        } else {
            durationMinutes = nil
        }

        guard let durationMinutes else {
            return
        }

        Task { @MainActor in
            if appState.hasTimedServerModeLimit,
               appState.timedServerModeSelectedDurationMinutes == durationMinutes {
                appState.clearTimedServerModeTimer()
            } else {
                await appState.startTimedServerMode(durationMinutes: durationMinutes)
            }
            updateStatusButton()
            refreshMenuSoon()
        }
    }

    @objc private func showTimedServerModeSettings(_ sender: Any?) {
        menu.cancelTracking()

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            if self.timedServerModeSettingsWindowController == nil {
                self.timedServerModeSettingsWindowController = TimedServerModeSettingsWindowController(
                    appState: self.appState
                )
            }
            self.timedServerModeSettingsWindowController?.show()
        }
    }

    @objc private func showLowBatterySettings(_ sender: Any?) {
        menu.cancelTracking()

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            if self.lowBatterySettingsWindowController == nil {
                self.lowBatterySettingsWindowController = LowBatterySettingsWindowController(appState: self.appState)
            }
            self.lowBatterySettingsWindowController?.show()
        }
    }

    @objc private func showShortcutSettings(_ sender: Any?) {
        menu.cancelTracking()

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            if self.shortcutSettingsWindowController == nil {
                self.shortcutSettingsWindowController = ShortcutSettingsWindowController()
            }
            self.shortcutSettingsWindowController?.show()
        }
    }

    @objc private func showAbout() {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController(appState: appState)
        }

        aboutWindowController?.show()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private enum MenuRowMetric {
    static let width: CGFloat = 286
    static let submenuWidth: CGFloat = 190
    static let height: CGFloat = 30
    static let memoryRowHeight: CGFloat = 32
    static let textHeight: CGFloat = 26
    static let indicatorLeading: CGFloat = 8
    static let indicatorWidth: CGFloat = 18
    static let titleLeading: CGFloat = 34
    static let trailing: CGFloat = 10
    static let shortcutTrailing: CGFloat = 12
    static let memoryValueWidth: CGFloat = 68
    static let cpuSeparatorWidth: CGFloat = 10
    static let cpuTitleWidth: CGFloat = 24
    static let cpuValueWidth: CGFloat = 42
}

private enum MenuItemState {
    case off
    case on
    case mixed

    var glyph: String {
        switch self {
        case .off:
            return ""
        case .on:
            return "✓"
        case .mixed:
            return "−"
        }
    }
}

private class HighlightedMenuRowView: NSView {
    var isRowEnabled: Bool {
        didSet {
            updateHighlightAppearance()
        }
    }

    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet {
            updateHighlightAppearance()
        }
    }
    private var isPressed = false {
        didSet {
            updateHighlightAppearance()
        }
    }

    private var isHighlighted: Bool {
        isRowEnabled && (isHovered || isPressed)
    }

    init(width: CGFloat, height: CGFloat, isRowEnabled: Bool) {
        self.isRowEnabled = isRowEnabled
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard isHighlighted else {
            return
        }

        let highlightRect = bounds.insetBy(dx: 5, dy: 2)
        let path = NSBezierPath(roundedRect: highlightRect, xRadius: 5, yRadius: 5)
        let color = isPressed
            ? NSColor.selectedMenuItemColor.withAlphaComponent(0.88)
            : NSColor.selectedMenuItemColor
        color.setFill()
        path.fill()
    }

    fileprivate func setPressed(_ isPressed: Bool) {
        self.isPressed = isPressed
    }

    fileprivate func contentTextColor(isHighlighted: Bool) -> NSColor {
        guard isRowEnabled else {
            return .disabledControlTextColor
        }

        return isHighlighted ? .selectedMenuItemTextColor : .labelColor
    }

    fileprivate func updateHighlightAppearance() {
        needsDisplay = true
        applyHighlightAppearance(isHighlighted: isHighlighted)
    }

    fileprivate func applyHighlightAppearance(isHighlighted: Bool) {}

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }
}

private final class MenuRowButton: NSButton {
    weak var rowView: HighlightedMenuRowView?
    var representedObject: Any?

    override var acceptsFirstResponder: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        rowView?.setPressed(true)
        super.mouseDown(with: event)
        rowView?.setPressed(false)
    }
}

private final class MenuStateActionRowView: HighlightedMenuRowView {
    private let checkmarkLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let actionButton = MenuRowButton()

    init(
        title: String,
        state: MenuItemState,
        isEnabled: Bool,
        target: AnyObject,
        action: Selector,
        representedObject: Any?,
        width: CGFloat
    ) {
        super.init(width: width, height: MenuRowMetric.height, isRowEnabled: isEnabled)

        checkmarkLabel.stringValue = state.glyph
        checkmarkLabel.alignment = .center
        checkmarkLabel.font = NSFont.menuFont(ofSize: 0)
        checkmarkLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = NSFont.menuFont(ofSize: 0)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        actionButton.isBordered = false
        actionButton.isTransparent = true
        actionButton.focusRingType = .none
        actionButton.title = ""
        actionButton.target = target
        actionButton.action = action
        actionButton.representedObject = representedObject
        actionButton.isEnabled = isEnabled
        actionButton.rowView = self
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(checkmarkLabel)
        addSubview(titleLabel)
        addSubview(actionButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: MenuRowMetric.height),
            widthAnchor.constraint(equalToConstant: width),

            checkmarkLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuRowMetric.indicatorLeading),
            checkmarkLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkmarkLabel.widthAnchor.constraint(equalToConstant: MenuRowMetric.indicatorWidth),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuRowMetric.titleLeading),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -MenuRowMetric.trailing),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            actionButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionButton.topAnchor.constraint(equalTo: topAnchor),
            actionButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        updateHighlightAppearance()
    }

    func update(title: String, state: MenuItemState, isEnabled: Bool) {
        titleLabel.stringValue = title
        checkmarkLabel.stringValue = state.glyph
        actionButton.isEnabled = isEnabled
        isRowEnabled = isEnabled
        needsLayout = true
        needsDisplay = true
    }

    override fileprivate func applyHighlightAppearance(isHighlighted: Bool) {
        let color = contentTextColor(isHighlighted: isHighlighted)
        checkmarkLabel.textColor = color
        titleLabel.textColor = color
    }
}

private final class MenuActionRowView: HighlightedMenuRowView {
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let actionButton = MenuRowButton()

    init(
        title: String,
        image: NSImage?,
        shortcutTitle: String? = nil,
        isEnabled: Bool,
        target: AnyObject,
        action: Selector,
        width: CGFloat = MenuRowMetric.width,
        height: CGFloat = MenuRowMetric.height
    ) {
        super.init(width: width, height: height, isRowEnabled: isEnabled)

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = NSFont.menuFont(ofSize: 0)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        shortcutLabel.stringValue = shortcutTitle ?? ""
        shortcutLabel.font = NSFont.menuFont(ofSize: 0)
        shortcutLabel.textColor = .tertiaryLabelColor
        shortcutLabel.lineBreakMode = .byTruncatingTail
        shortcutLabel.alignment = .right
        shortcutLabel.isHidden = shortcutTitle == nil
        shortcutLabel.setContentHuggingPriority(.required, for: .horizontal)
        shortcutLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        actionButton.isBordered = false
        actionButton.isTransparent = true
        actionButton.focusRingType = .none
        actionButton.title = ""
        actionButton.target = target
        actionButton.action = action
        actionButton.isEnabled = isEnabled
        actionButton.rowView = self
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        addSubview(titleLabel)
        addSubview(shortcutLabel)
        addSubview(actionButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height),
            widthAnchor.constraint(equalToConstant: width),

            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuRowMetric.indicatorLeading),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: MenuRowMetric.indicatorWidth),
            imageView.heightAnchor.constraint(equalToConstant: MenuRowMetric.indicatorWidth),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuRowMetric.titleLeading),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            shortcutLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 10),
            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuRowMetric.shortcutTrailing),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            actionButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionButton.topAnchor.constraint(equalTo: topAnchor),
            actionButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        updateHighlightAppearance()
    }

    func update(title: String, image: NSImage?, shortcutTitle: String?, isEnabled: Bool) {
        titleLabel.stringValue = title
        imageView.image = image
        shortcutLabel.stringValue = shortcutTitle ?? ""
        shortcutLabel.isHidden = shortcutTitle == nil
        actionButton.isEnabled = isEnabled
        isRowEnabled = isEnabled
        needsLayout = true
        needsDisplay = true
    }

    override fileprivate func applyHighlightAppearance(isHighlighted: Bool) {
        let color = contentTextColor(isHighlighted: isHighlighted)
        titleLabel.textColor = color
        imageView.contentTintColor = color
        shortcutLabel.textColor = isHighlighted ? color : .tertiaryLabelColor
        imageView.alphaValue = isRowEnabled ? 1 : 0.45
    }
}

private final class MenuDisclosureChevronView: NSView {
    var isExpanded: Bool {
        didSet {
            needsDisplay = true
        }
    }
    var strokeColor: NSColor {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    init(isExpanded: Bool, strokeColor: NSColor = .tertiaryLabelColor) {
        self.isExpanded = isExpanded
        self.strokeColor = strokeColor
        super.init(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        translatesAutoresizingMaskIntoConstraints = false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let path = NSBezierPath()
        path.lineWidth = 1.55
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        if isExpanded {
            path.move(to: NSPoint(x: center.x - 3.5, y: center.y - 1.8))
            path.line(to: NSPoint(x: center.x, y: center.y + 2.0))
            path.line(to: NSPoint(x: center.x + 3.5, y: center.y - 1.8))
        } else {
            path.move(to: NSPoint(x: center.x - 1.7, y: center.y - 3.6))
            path.line(to: NSPoint(x: center.x + 2.2, y: center.y))
            path.line(to: NSPoint(x: center.x - 1.7, y: center.y + 3.6))
        }

        strokeColor.setStroke()
        path.stroke()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }
}

private final class MenuMemorySectionHeaderRowView: HighlightedMenuRowView {
    private let disclosureView: MenuDisclosureChevronView
    private let titleLabel = NSTextField(labelWithString: "")
    private let memoryLabel = NSTextField(labelWithString: "")
    private let separatorLabel = NSTextField(labelWithString: "·")
    private let cpuTitleLabel = NSTextField(labelWithString: "CPU")
    private let cpuValueLabel = NSTextField(labelWithString: "")
    private let actionButton = MenuRowButton()
    private let onHoverBegan: (NSView) -> Void
    private let onHoverEnded: () -> Void
    private var isExpanded: Bool

    init(
        title: String,
        memoryDetail: String,
        cpuDetail: String,
        isExpanded: Bool,
        target: AnyObject,
        action: Selector,
        onHoverBegan: @escaping (NSView) -> Void,
        onHoverEnded: @escaping () -> Void
    ) {
        self.onHoverBegan = onHoverBegan
        self.onHoverEnded = onHoverEnded
        self.isExpanded = isExpanded
        self.disclosureView = MenuDisclosureChevronView(isExpanded: isExpanded)

        super.init(width: MenuRowMetric.width, height: MenuRowMetric.height, isRowEnabled: true)

        titleLabel.stringValue = title
        titleLabel.font = NSFont.menuFont(ofSize: 0)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        memoryLabel.stringValue = memoryDetail
        memoryLabel.font = Self.memoryFont(isExpanded: isExpanded)
        memoryLabel.textColor = Self.memoryTextColor(isExpanded: isExpanded, isHighlighted: false)
        memoryLabel.alignment = .right
        memoryLabel.lineBreakMode = .byTruncatingTail
        memoryLabel.setContentHuggingPriority(.required, for: .horizontal)
        memoryLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        memoryLabel.translatesAutoresizingMaskIntoConstraints = false

        [separatorLabel, cpuTitleLabel, cpuValueLabel].forEach { label in
            label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .tertiaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            label.translatesAutoresizingMaskIntoConstraints = false
        }
        separatorLabel.alignment = .center
        cpuTitleLabel.alignment = .right
        cpuValueLabel.stringValue = cpuDetail
        cpuValueLabel.alignment = .right

        actionButton.isBordered = false
        actionButton.isTransparent = true
        actionButton.focusRingType = .none
        actionButton.title = ""
        actionButton.target = target
        actionButton.action = action
        actionButton.rowView = self
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(disclosureView)
        addSubview(titleLabel)
        addSubview(memoryLabel)
        addSubview(separatorLabel)
        addSubview(cpuTitleLabel)
        addSubview(cpuValueLabel)
        addSubview(actionButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: MenuRowMetric.height),
            widthAnchor.constraint(equalToConstant: MenuRowMetric.width),

            disclosureView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuRowMetric.indicatorLeading),
            disclosureView.centerYAnchor.constraint(equalTo: centerYAnchor),
            disclosureView.widthAnchor.constraint(equalToConstant: MenuRowMetric.indicatorWidth),
            disclosureView.heightAnchor.constraint(equalToConstant: MenuRowMetric.indicatorWidth),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuRowMetric.titleLeading),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: memoryLabel.leadingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            memoryLabel.widthAnchor.constraint(equalToConstant: MenuRowMetric.memoryValueWidth),
            memoryLabel.trailingAnchor.constraint(equalTo: separatorLabel.leadingAnchor, constant: -6),
            memoryLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            separatorLabel.widthAnchor.constraint(equalToConstant: MenuRowMetric.cpuSeparatorWidth),
            separatorLabel.trailingAnchor.constraint(equalTo: cpuTitleLabel.leadingAnchor, constant: -4),
            separatorLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            cpuTitleLabel.widthAnchor.constraint(equalToConstant: MenuRowMetric.cpuTitleWidth),
            cpuTitleLabel.trailingAnchor.constraint(equalTo: cpuValueLabel.leadingAnchor, constant: -4),
            cpuTitleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            cpuValueLabel.widthAnchor.constraint(equalToConstant: MenuRowMetric.cpuValueWidth),
            cpuValueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuRowMetric.shortcutTrailing),
            cpuValueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            actionButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionButton.topAnchor.constraint(equalTo: topAnchor),
            actionButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        updateHighlightAppearance()
    }

    func update(title: String, memoryDetail: String, cpuDetail: String, isExpanded: Bool) {
        titleLabel.stringValue = title
        memoryLabel.stringValue = memoryDetail
        cpuValueLabel.stringValue = cpuDetail
        self.isExpanded = isExpanded
        memoryLabel.font = Self.memoryFont(isExpanded: isExpanded)
        disclosureView.isExpanded = isExpanded
        updateHighlightAppearance()
        needsLayout = true
        needsDisplay = true
    }

    override fileprivate func applyHighlightAppearance(isHighlighted: Bool) {
        let color = contentTextColor(isHighlighted: isHighlighted)
        disclosureView.strokeColor = isHighlighted ? color : .tertiaryLabelColor
        titleLabel.textColor = color
        memoryLabel.textColor = Self.memoryTextColor(isExpanded: isExpanded, isHighlighted: isHighlighted)
        let secondaryColor = isHighlighted ? color : NSColor.tertiaryLabelColor
        separatorLabel.textColor = secondaryColor
        cpuTitleLabel.textColor = secondaryColor
        cpuValueLabel.textColor = secondaryColor
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverBegan(self)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverEnded()
    }

    private static func memoryFont(isExpanded: Bool) -> NSFont {
        .monospacedSystemFont(ofSize: 11, weight: isExpanded ? .semibold : .regular)
    }

    private static func memoryTextColor(isExpanded: Bool, isHighlighted: Bool) -> NSColor {
        if isHighlighted {
            return .selectedMenuItemTextColor
        }

        return isExpanded ? .labelColor : .tertiaryLabelColor
    }
}

private final class MenuMemoryAppRowView: NSView {
    private let imageView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let memoryLabel = NSTextField(labelWithString: "")
    private let separatorLabel = NSTextField(labelWithString: "·")
    private let cpuTitleLabel = NSTextField(labelWithString: "CPU")
    private let cpuValueLabel = NSTextField(labelWithString: "")
    private let onHoverBegan: (MemoryUsageApp, NSView) -> Void
    private let onHoverEnded: (MemoryUsageApp) -> Void
    private var currentApp: MemoryUsageApp
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false

    init(
        app: MemoryUsageApp,
        onHoverBegan: @escaping (MemoryUsageApp, NSView) -> Void,
        onHoverEnded: @escaping (MemoryUsageApp) -> Void
    ) {
        currentApp = app
        self.onHoverBegan = onHoverBegan
        self.onHoverEnded = onHoverEnded

        super.init(
            frame: NSRect(
                x: 0,
                y: 0,
                width: MenuRowMetric.width,
                height: MenuRowMetric.memoryRowHeight
            )
        )

        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = NSFont.menuFont(ofSize: 0)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        memoryLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        memoryLabel.textColor = .labelColor
        memoryLabel.alignment = .right
        memoryLabel.lineBreakMode = .byTruncatingTail
        memoryLabel.setContentHuggingPriority(.required, for: .horizontal)
        memoryLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        memoryLabel.translatesAutoresizingMaskIntoConstraints = false

        [separatorLabel, cpuTitleLabel, cpuValueLabel].forEach { label in
            label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .tertiaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            label.translatesAutoresizingMaskIntoConstraints = false
        }
        separatorLabel.alignment = .center
        cpuTitleLabel.alignment = .right
        cpuValueLabel.alignment = .right

        addSubview(imageView)
        addSubview(nameLabel)
        addSubview(memoryLabel)
        addSubview(separatorLabel)
        addSubview(cpuTitleLabel)
        addSubview(cpuValueLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: MenuRowMetric.memoryRowHeight),
            widthAnchor.constraint(equalToConstant: MenuRowMetric.width),

            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuRowMetric.indicatorLeading),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: MenuRowMetric.indicatorWidth),
            imageView.heightAnchor.constraint(equalToConstant: MenuRowMetric.indicatorWidth),

            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuRowMetric.titleLeading),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: memoryLabel.leadingAnchor, constant: -10),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            memoryLabel.widthAnchor.constraint(equalToConstant: MenuRowMetric.memoryValueWidth),
            memoryLabel.trailingAnchor.constraint(equalTo: separatorLabel.leadingAnchor, constant: -6),
            memoryLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            separatorLabel.widthAnchor.constraint(equalToConstant: MenuRowMetric.cpuSeparatorWidth),
            separatorLabel.trailingAnchor.constraint(equalTo: cpuTitleLabel.leadingAnchor, constant: -4),
            separatorLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            cpuTitleLabel.widthAnchor.constraint(equalToConstant: MenuRowMetric.cpuTitleWidth),
            cpuTitleLabel.trailingAnchor.constraint(equalTo: cpuValueLabel.leadingAnchor, constant: -4),
            cpuTitleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            cpuValueLabel.widthAnchor.constraint(equalToConstant: MenuRowMetric.cpuValueWidth),
            cpuValueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuRowMetric.shortcutTrailing),
            cpuValueLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        update(app: app)
    }

    func update(app: MemoryUsageApp) {
        currentApp = app
        imageView.image = app.icon
        nameLabel.stringValue = app.name
        memoryLabel.stringValue = app.memoryDisplay
        cpuValueLabel.stringValue = app.percentDisplay
        needsLayout = true
        needsDisplay = true

        if isHovering {
            onHoverBegan(app, self)
        }
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea

        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        onHoverBegan(currentApp, self)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        onHoverEnded(currentApp)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }
}

private final class MemoryTrendPanelController {
    private static let panelSize = NSSize(width: 248, height: 164)

    private let contentView = MemoryTrendPanelView()
    private var panel: NSPanel?
    private(set) var visibleAppID: String?

    func show(history: MemoryUsageHistory, relativeTo anchorView: NSView) {
        update(history: history)

        let panel = existingOrNewPanel()
        position(panel: panel, relativeTo: anchorView)
        panel.orderFront(nil)
    }

    func show(systemHistory: SystemPressureHistory, relativeTo anchorView: NSView) {
        update(systemHistory: systemHistory)

        let panel = existingOrNewPanel()
        position(panel: panel, relativeTo: anchorView)
        panel.orderFront(nil)
    }

    func update(history: MemoryUsageHistory) {
        visibleAppID = history.appID
        contentView.update(history: history)
    }

    func update(systemHistory: SystemPressureHistory) {
        visibleAppID = SystemPressureHistory.id
        contentView.update(systemHistory: systemHistory)
    }

    func hide() {
        visibleAppID = nil
        panel?.orderOut(nil)
    }

    private func existingOrNewPanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = contentView
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        self.panel = panel
        return panel
    }

    private func position(panel: NSPanel, relativeTo anchorView: NSView) {
        guard let window = anchorView.window else {
            return
        }

        let anchorRectInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorRect = window.convertToScreen(anchorRectInWindow)
        let screenFrame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let margin: CGFloat = 8
        let size = Self.panelSize

        var origin = NSPoint(
            x: anchorRect.maxX + margin,
            y: anchorRect.midY - size.height / 2
        )

        if origin.x + size.width > screenFrame.maxX - margin {
            origin.x = anchorRect.minX - size.width - margin
        }

        origin.y = min(
            max(origin.y, screenFrame.minY + margin),
            screenFrame.maxY - size.height - margin
        )

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

private final class MemoryTrendPanelView: NSVisualEffectView {
    private static let preferredSize = NSSize(width: 248, height: 164)
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.includesActualByteCount = false
        formatter.isAdaptive = true
        return formatter
    }()

    private let titleLabel = NSTextField(labelWithString: "")
    private let rangeLabel = NSTextField(labelWithString: AppText.memoryTrendLast24Hours)
    private let currentLabel = NSTextField(labelWithString: "")
    private let peakLabel = NSTextField(labelWithString: "")
    private let chartView = MemoryTrendChartView()

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.preferredSize))

        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        updateLayerBorder()

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        rangeLabel.font = .systemFont(ofSize: 11, weight: .regular)
        rangeLabel.textColor = .secondaryLabelColor
        rangeLabel.alignment = .right
        rangeLabel.setContentHuggingPriority(.required, for: .horizontal)
        rangeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        rangeLabel.translatesAutoresizingMaskIntoConstraints = false

        currentLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        currentLabel.textColor = .labelColor
        currentLabel.lineBreakMode = .byTruncatingTail
        currentLabel.translatesAutoresizingMaskIntoConstraints = false

        peakLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        peakLabel.textColor = .secondaryLabelColor
        peakLabel.lineBreakMode = .byTruncatingTail
        peakLabel.translatesAutoresizingMaskIntoConstraints = false

        chartView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(rangeLabel)
        addSubview(currentLabel)
        addSubview(peakLabel)
        addSubview(chartView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.preferredSize.width),
            heightAnchor.constraint(equalToConstant: Self.preferredSize.height),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: rangeLabel.leadingAnchor, constant: -8),

            rangeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rangeLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            currentLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            currentLabel.trailingAnchor.constraint(equalTo: rangeLabel.trailingAnchor),
            currentLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),

            peakLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            peakLabel.trailingAnchor.constraint(equalTo: rangeLabel.trailingAnchor),
            peakLabel.topAnchor.constraint(equalTo: currentLabel.bottomAnchor, constant: 3),

            chartView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            chartView.trailingAnchor.constraint(equalTo: rangeLabel.trailingAnchor),
            chartView.topAnchor.constraint(equalTo: peakLabel.bottomAnchor, constant: 8),
            chartView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    func update(history: MemoryUsageHistory) {
        titleLabel.stringValue = history.appName
        titleLabel.toolTip = history.appName
        currentLabel.stringValue = AppText.memoryTrendCurrent(
            memory: Self.formattedBytes(history.currentBytes),
            cpu: Self.formattedCPU(history.currentCPUPercent)
        )
        peakLabel.stringValue = AppText.memoryTrendPeak(
            memory: Self.formattedBytes(history.peakBytes),
            cpu: Self.formattedCPU(history.peakCPUPercent)
        )
        chartView.update(history: history)
    }

    func update(systemHistory: SystemPressureHistory) {
        titleLabel.stringValue = AppText.memoryUsageSectionTitle
        titleLabel.toolTip = AppText.memoryUsageSectionTitle
        currentLabel.stringValue = AppText.memoryTrendCurrent(
            memory: Self.formattedBytes(systemHistory.current.memoryUsedBytes),
            cpu: Self.formattedCPU(systemHistory.current.cpuPercent)
        )
        peakLabel.stringValue = AppText.memoryTrendPeak(
            memory: Self.formattedBytes(systemHistory.peakMemoryUsedBytes),
            cpu: Self.formattedCPU(systemHistory.peakCPUPercent)
        )
        chartView.update(systemHistory: systemHistory)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerBorder()
    }

    private func updateLayerBorder() {
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
    }

    private static func formattedBytes(_ bytes: UInt64) -> String {
        byteFormatter.string(fromByteCount: Int64(bytes))
    }

    private static func formattedCPU(_ cpuPercent: Double) -> String {
        String(format: "%.1f%%", cpuPercent)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }
}

private final class MemoryTrendChartView: NSView {
    private struct ChartPoint {
        let timestamp: Date
        let memoryValue: Double
        let cpuPercent: Double
    }

    private enum ChartData {
        case app(MemoryUsageHistory)
        case system(SystemPressureHistory)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var chartData: ChartData?

    override var isFlipped: Bool {
        false
    }

    func update(history: MemoryUsageHistory) {
        chartData = .app(history)
        needsDisplay = true
    }

    func update(systemHistory: SystemPressureHistory) {
        chartData = .system(systemHistory)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let timeLabelHeight: CGFloat = 14
        let chartRect = NSRect(
            x: bounds.minX + 2,
            y: bounds.minY + timeLabelHeight + 4,
            width: max(bounds.width - 4, 0),
            height: max(bounds.height - timeLabelHeight - 8, 0)
        )
        guard chartRect.width > 1, chartRect.height > 1 else {
            return
        }

        drawGrid(in: chartRect)

        guard let chartData else {
            let now = Date()
            drawTimeLabels(startDate: now.addingTimeInterval(-24 * 60 * 60), endDate: now)
            return
        }

        let now = Date()
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        let points: [ChartPoint]
        let memoryScale: Double
        switch chartData {
        case .app(let history):
            points = history.points
                .filter { $0.timestamp >= cutoff }
                .sorted { $0.timestamp < $1.timestamp }
                .map { point in
                    ChartPoint(
                        timestamp: point.timestamp,
                        memoryValue: Double(point.residentBytes),
                        cpuPercent: point.cpuPercent
                    )
                }
            memoryScale = max(points.map(\.memoryValue).max() ?? 0, 1)
        case .system(let history):
            points = history.points
                .filter { $0.timestamp >= cutoff }
                .sorted { $0.timestamp < $1.timestamp }
                .map { point in
                    ChartPoint(
                        timestamp: point.timestamp,
                        memoryValue: point.memoryPercent,
                        cpuPercent: point.cpuPercent
                    )
                }
            memoryScale = 100
        }

        guard let firstPoint = points.first else {
            drawTimeLabels(startDate: cutoff, endDate: now)
            return
        }

        let firstTimestamp = max(cutoff.timeIntervalSinceReferenceDate, firstPoint.timestamp.timeIntervalSinceReferenceDate)
        let lastTimestamp = max(now.timeIntervalSinceReferenceDate, points.last?.timestamp.timeIntervalSinceReferenceDate ?? firstTimestamp)
        let startDate = Date(timeIntervalSinceReferenceDate: firstTimestamp)
        let endDate = Date(timeIntervalSinceReferenceDate: lastTimestamp)
        let timestampRange = max(lastTimestamp - firstTimestamp, 1)
        let maxCPUPercent = max(points.map(\.cpuPercent).max() ?? 0, 100)
        let hasSinglePoint = points.count == 1

        let xPosition: (ChartPoint) -> CGFloat = { point in
            let xRatio = hasSinglePoint
                ? 1
                : (point.timestamp.timeIntervalSinceReferenceDate - firstTimestamp) / timestampRange
            return chartRect.minX + chartRect.width * min(max(CGFloat(xRatio), 0), 1)
        }

        let makeMemoryPoint: (ChartPoint) -> NSPoint = { point in
            let yRatio = point.memoryValue / memoryScale
            return NSPoint(
                x: xPosition(point),
                y: chartRect.minY + chartRect.height * min(max(CGFloat(yRatio), 0), 1)
            )
        }

        let makeCPUPoint: (ChartPoint) -> NSPoint = { point in
            let yRatio = point.cpuPercent / maxCPUPercent
            return NSPoint(
                x: xPosition(point),
                y: chartRect.minY + chartRect.height * min(max(CGFloat(yRatio), 0), 1)
            )
        }

        let memoryPoints = points.map(makeMemoryPoint)
        let cpuPoints = points.map(makeCPUPoint)

        drawMemoryWater(points: memoryPoints, in: chartRect)
        drawLine(points: cpuPoints, color: NSColor.controlAccentColor.withAlphaComponent(0.95), lineWidth: 2)
        drawEndpoint(at: makeCPUPoint(points.last ?? firstPoint), color: .controlAccentColor)
        drawTimeLabels(startDate: startDate, endDate: endDate)
    }

    private func drawGrid(in rect: NSRect) {
        let gridPath = NSBezierPath()
        for index in 0...2 {
            let y = rect.minY + rect.height * CGFloat(index) / 2
            gridPath.move(to: NSPoint(x: rect.minX, y: y))
            gridPath.line(to: NSPoint(x: rect.maxX, y: y))
        }

        NSColor.separatorColor.withAlphaComponent(0.32).setStroke()
        gridPath.lineWidth = 0.5
        gridPath.stroke()
    }

    private func drawMemoryWater(points: [NSPoint], in rect: NSRect) {
        guard let firstPoint = points.first, let lastPoint = points.last else {
            return
        }

        let fillPath = NSBezierPath()
        fillPath.move(to: NSPoint(x: firstPoint.x, y: rect.minY))
        points.forEach { fillPath.line(to: $0) }
        fillPath.line(to: NSPoint(x: lastPoint.x, y: rect.minY))
        fillPath.close()

        NSColor.systemBlue.withAlphaComponent(0.16).setFill()
        fillPath.fill()
        drawLine(points: points, color: NSColor.systemBlue.withAlphaComponent(0.28), lineWidth: 1)
    }

    private func drawLine(points: [NSPoint], color: NSColor, lineWidth: CGFloat) {
        let linePath = NSBezierPath()
        for (index, point) in points.enumerated() {
            if index == 0 {
                linePath.move(to: point)
            } else {
                linePath.line(to: point)
            }
        }

        color.setStroke()
        linePath.lineWidth = lineWidth
        linePath.lineJoinStyle = .round
        linePath.lineCapStyle = .round
        linePath.stroke()
    }

    private func drawEndpoint(at point: NSPoint, color: NSColor) {
        let dotRect = NSRect(
            x: point.x - 2.5,
            y: point.y - 2.5,
            width: 5,
            height: 5
        )
        color.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    private func drawTimeLabels(startDate: Date, endDate: Date) {
        let startTimestamp = startDate.timeIntervalSinceReferenceDate
        let endTimestamp = max(endDate.timeIntervalSinceReferenceDate, startTimestamp)
        let middleDate = Date(timeIntervalSinceReferenceDate: (startTimestamp + endTimestamp) / 2)
        let y: CGFloat = bounds.minY
        let height: CGFloat = 12
        let labelWidth: CGFloat = 58
        let centerWidth: CGFloat = 70

        drawTimeLabel(
            Self.timeFormatter.string(from: startDate),
            in: NSRect(x: bounds.minX + 1, y: y, width: labelWidth, height: height),
            alignment: .left
        )
        drawTimeLabel(
            Self.timeFormatter.string(from: middleDate),
            in: NSRect(x: bounds.midX - centerWidth / 2, y: y, width: centerWidth, height: height),
            alignment: .center
        )
        drawTimeLabel(
            Self.timeFormatter.string(from: endDate),
            in: NSRect(x: bounds.maxX - labelWidth - 1, y: y, width: labelWidth, height: height),
            alignment: .right
        )
    }

    private func drawTimeLabel(_ label: String, in rect: NSRect, alignment: NSTextAlignment) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.68),
            .paragraphStyle: paragraphStyle
        ]
        NSString(string: label).draw(in: rect, withAttributes: attributes)
    }
}

private final class MenuTextRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuRowMetric.width, height: MenuRowMetric.textHeight))

        titleLabel.stringValue = title
        titleLabel.font = NSFont.menuFont(ofSize: 0)
        titleLabel.textColor = .disabledControlTextColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: MenuRowMetric.textHeight),
            widthAnchor.constraint(equalToConstant: MenuRowMetric.width),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuRowMetric.titleLeading),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -MenuRowMetric.trailing),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func update(title: String) {
        titleLabel.stringValue = title
        needsLayout = true
        needsDisplay = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }
}

private final class MenuSubmenuRowView: HighlightedMenuRowView {
    private let checkmarkLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let chevronLabel = NSTextField(labelWithString: "›")

    init(title: String, isOn: Bool, isEnabled: Bool) {
        super.init(width: MenuRowMetric.width, height: MenuRowMetric.height, isRowEnabled: isEnabled)

        checkmarkLabel.stringValue = isOn ? "✓" : ""
        checkmarkLabel.alignment = .center
        checkmarkLabel.font = NSFont.menuFont(ofSize: 0)
        checkmarkLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = NSFont.menuFont(ofSize: 0)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        chevronLabel.alignment = .right
        chevronLabel.font = NSFont.menuFont(ofSize: 0)
        chevronLabel.setContentHuggingPriority(.required, for: .horizontal)
        chevronLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        chevronLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(checkmarkLabel)
        addSubview(titleLabel)
        addSubview(chevronLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: MenuRowMetric.height),
            widthAnchor.constraint(equalToConstant: MenuRowMetric.width),

            checkmarkLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuRowMetric.indicatorLeading),
            checkmarkLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkmarkLabel.widthAnchor.constraint(equalToConstant: MenuRowMetric.indicatorWidth),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuRowMetric.titleLeading),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronLabel.leadingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevronLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuRowMetric.shortcutTrailing),
            chevronLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateHighlightAppearance()
    }

    func update(title: String, isOn: Bool, isEnabled: Bool) {
        titleLabel.stringValue = title
        checkmarkLabel.stringValue = isOn ? "✓" : ""
        isRowEnabled = isEnabled
        needsLayout = true
        needsDisplay = true
    }

    override fileprivate func applyHighlightAppearance(isHighlighted: Bool) {
        let color = contentTextColor(isHighlighted: isHighlighted)
        checkmarkLabel.textColor = color
        titleLabel.textColor = color
        chevronLabel.textColor = isHighlighted ? color : .tertiaryLabelColor
    }
}

private final class MenuToggleRowView: HighlightedMenuRowView {
    private let checkmarkLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let toggleOverlayButton = MenuRowButton()

    init(
        title: String,
        isOn: Bool,
        isToggleEnabled: Bool,
        tooltip: String? = nil,
        shortcutTitle: String? = nil,
        settingsButtonTitle: String? = nil,
        target: AnyObject,
        toggleAction: Selector,
        settingsAction: Selector? = nil
    ) {
        super.init(width: MenuRowMetric.width, height: MenuRowMetric.height, isRowEnabled: isToggleEnabled)

        checkmarkLabel.stringValue = isOn ? "✓" : ""
        checkmarkLabel.alignment = .center
        checkmarkLabel.font = NSFont.menuFont(ofSize: 0)
        checkmarkLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = NSFont.menuFont(ofSize: 0)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        shortcutLabel.stringValue = shortcutTitle ?? ""
        shortcutLabel.font = NSFont.menuFont(ofSize: 0)
        shortcutLabel.textColor = .tertiaryLabelColor
        shortcutLabel.lineBreakMode = .byTruncatingTail
        shortcutLabel.alignment = .right
        shortcutLabel.isHidden = shortcutTitle == nil
        shortcutLabel.setContentHuggingPriority(.required, for: .horizontal)
        shortcutLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        toggleOverlayButton.isBordered = false
        toggleOverlayButton.isTransparent = true
        toggleOverlayButton.focusRingType = .none
        toggleOverlayButton.title = ""
        toggleOverlayButton.target = target
        toggleOverlayButton.action = toggleAction
        toggleOverlayButton.isEnabled = isToggleEnabled
        toggleOverlayButton.rowView = self
        toggleOverlayButton.toolTip = isToggleEnabled ? nil : tooltip
        toggleOverlayButton.translatesAutoresizingMaskIntoConstraints = false

        let settingsButton: NSButton?
        if let settingsButtonTitle, let settingsAction {
            let button = NSButton(title: settingsButtonTitle, target: target, action: settingsAction)
            button.font = NSFont.systemFont(ofSize: 11)
            button.controlSize = .small
            button.bezelStyle = .rounded
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.translatesAutoresizingMaskIntoConstraints = false
            settingsButton = button
        } else {
            settingsButton = nil
        }

        addSubview(checkmarkLabel)
        addSubview(titleLabel)
        addSubview(shortcutLabel)
        addSubview(toggleOverlayButton)
        if let settingsButton {
            addSubview(settingsButton)
        }

        var constraints: [NSLayoutConstraint] = [
            heightAnchor.constraint(equalToConstant: MenuRowMetric.height),
            widthAnchor.constraint(equalToConstant: MenuRowMetric.width),

            checkmarkLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuRowMetric.indicatorLeading),
            checkmarkLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkmarkLabel.widthAnchor.constraint(equalToConstant: MenuRowMetric.indicatorWidth),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuRowMetric.titleLeading),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            toggleOverlayButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            toggleOverlayButton.topAnchor.constraint(equalTo: topAnchor),
            toggleOverlayButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]

        if let settingsButton {
            constraints += [
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: settingsButton.leadingAnchor, constant: -8),
                shortcutLabel.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -8),
                toggleOverlayButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -6),
                settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuRowMetric.trailing),
                settingsButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                settingsButton.widthAnchor.constraint(equalToConstant: 64)
            ]
        } else {
            constraints += [
                shortcutLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 10),
                shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuRowMetric.shortcutTrailing),
                toggleOverlayButton.trailingAnchor.constraint(equalTo: trailingAnchor)
            ]
        }

        constraints += [
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: shortcutLabel.leadingAnchor, constant: -10),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ]

        NSLayoutConstraint.activate(constraints)
        updateHighlightAppearance()
    }

    func update(
        title: String,
        isOn: Bool,
        isToggleEnabled: Bool,
        tooltip: String? = nil,
        shortcutTitle: String? = nil
    ) {
        titleLabel.stringValue = title
        checkmarkLabel.stringValue = isOn ? "✓" : ""
        shortcutLabel.stringValue = shortcutTitle ?? ""
        shortcutLabel.isHidden = shortcutTitle == nil
        toggleOverlayButton.isEnabled = isToggleEnabled
        toggleOverlayButton.toolTip = isToggleEnabled ? nil : tooltip
        isRowEnabled = isToggleEnabled
        needsLayout = true
        needsDisplay = true
    }

    override fileprivate func applyHighlightAppearance(isHighlighted: Bool) {
        let color = contentTextColor(isHighlighted: isHighlighted)
        checkmarkLabel.textColor = color
        titleLabel.textColor = color
        subviews.compactMap { $0 as? NSTextField }
            .filter { $0 !== checkmarkLabel && $0 !== titleLabel }
            .forEach { $0.textColor = isHighlighted ? color : .tertiaryLabelColor }
    }
}

private enum MenuBarStatusIconRenderer {
    static func menuServerModeImage(for style: MenuBarIconStyle, fallbackSystemName _: String) -> NSImage? {
        switch style {
        case .idle:
            return nil
        case .waitingForPowerAdapter:
            return menuStatusLight(color: .systemOrange)
        case .serverModePowerOnly:
            return menuStatusLight(color: .systemGreen)
        case .serverModeBatteryAllowed:
            return menuStatusLight(color: .systemRed)
        }
    }

    static func image(for style: MenuBarIconStyle) -> NSImage? {
        switch style {
        case .idle:
            let image = (NSImage(named: "MenuBarIcon") ?? systemImage(named: "server.rack"))?.copy() as? NSImage
            image?.size = NSSize(width: 18, height: 18)
            image?.cacheMode = .never
            image?.isTemplate = true
            return image
        case .waitingForPowerAdapter:
            return statusDot(color: .systemOrange, text: "S")
        case .serverModePowerOnly:
            return statusDot(color: .systemGreen, text: "S")
        case .serverModeBatteryAllowed:
            return statusDot(color: .systemRed, text: "B")
        }
    }

    static func systemImage(named name: String) -> NSImage? {
        if #available(macOS 11.0, *) {
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }

        return nil
    }

    static func title(for style: MenuBarIconStyle) -> String {
        switch style {
        case .idle:
            return ""
        case .waitingForPowerAdapter:
            return ""
        case .serverModePowerOnly:
            return ""
        case .serverModeBatteryAllowed:
            return ""
        }
    }

    private static func statusDot(color: NSColor, text: String) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let bounds = NSRect(origin: .zero, size: size)
        let circleRect = NSRect(
            x: bounds.midX - 7.5,
            y: bounds.midY - 7.5,
            width: 15,
            height: 15
        )
        let circle = NSBezierPath(ovalIn: circleRect)
        color.setFill()
        circle.fill()

        NSColor.white.withAlphaComponent(0.95).setStroke()
        circle.lineWidth = 1
        circle.stroke()

        drawStatusLetter(text, in: bounds)

        image.cacheMode = .never
        image.isTemplate = false
        return image
    }

    private static func drawStatusLetter(_ text: String, in bounds: NSRect) {
        let targetRect = NSRect(
            x: bounds.midX - 2.9,
            y: bounds.midY - 3.4,
            width: 5.8,
            height: 6.8
        )

        guard let scalar = text.unicodeScalars.first,
              scalar.value <= UInt16.max,
              let context = NSGraphicsContext.current?.cgContext else {
            drawFallbackStatusLetter(text, in: targetRect)
            return
        }

        let font = NSFont(name: "PingFangSC-Semibold", size: 10.8)
            ?? NSFont.systemFont(ofSize: 10.8, weight: .semibold)
        let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        var character = UniChar(scalar.value)
        var glyph = CGGlyph()

        guard CTFontGetGlyphsForCharacters(ctFont, &character, &glyph, 1),
              let glyphPath = CTFontCreatePathForGlyph(ctFont, glyph, nil) else {
            drawFallbackStatusLetter(text, in: targetRect)
            return
        }

        let glyphBounds = glyphPath.boundingBoxOfPath
        guard glyphBounds.width > 0, glyphBounds.height > 0 else {
            drawFallbackStatusLetter(text, in: targetRect)
            return
        }

        let scale = min(targetRect.width / glyphBounds.width, targetRect.height / glyphBounds.height)

        context.saveGState()
        context.setShouldAntialias(true)
        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineJoin(.round)
        context.setLineWidth(0.22)
        context.translateBy(x: targetRect.midX, y: targetRect.midY - 0.05)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -glyphBounds.midX, y: -glyphBounds.midY)
        context.addPath(glyphPath)
        context.drawPath(using: .fillStroke)
        context.restoreGState()
    }

    private static func drawFallbackStatusLetter(_ text: String, in rect: NSRect) {
        let path: NSBezierPath
        switch text {
        case "B":
            path = statusLetterBPath(in: rect)
        default:
            path = statusLetterSPath(in: rect)
        }

        NSColor.white.setStroke()
        path.lineWidth = 1.7
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func statusLetterSPath(in rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: statusLetterPoint(x: 0.82, y: 0.88, in: rect))
        path.curve(
            to: statusLetterPoint(x: 0.20, y: 0.70, in: rect),
            controlPoint1: statusLetterPoint(x: 0.66, y: 0.98, in: rect),
            controlPoint2: statusLetterPoint(x: 0.30, y: 0.98, in: rect)
        )
        path.curve(
            to: statusLetterPoint(x: 0.48, y: 0.52, in: rect),
            controlPoint1: statusLetterPoint(x: 0.08, y: 0.55, in: rect),
            controlPoint2: statusLetterPoint(x: 0.24, y: 0.50, in: rect)
        )
        path.curve(
            to: statusLetterPoint(x: 0.80, y: 0.32, in: rect),
            controlPoint1: statusLetterPoint(x: 0.74, y: 0.54, in: rect),
            controlPoint2: statusLetterPoint(x: 0.92, y: 0.48, in: rect)
        )
        path.curve(
            to: statusLetterPoint(x: 0.18, y: 0.12, in: rect),
            controlPoint1: statusLetterPoint(x: 0.66, y: 0.02, in: rect),
            controlPoint2: statusLetterPoint(x: 0.34, y: 0.02, in: rect)
        )
        return path
    }

    private static func statusLetterBPath(in rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: statusLetterPoint(x: 0.22, y: 0.12, in: rect))
        path.line(to: statusLetterPoint(x: 0.22, y: 0.88, in: rect))

        path.move(to: statusLetterPoint(x: 0.22, y: 0.88, in: rect))
        path.curve(
            to: statusLetterPoint(x: 0.70, y: 0.70, in: rect),
            controlPoint1: statusLetterPoint(x: 0.58, y: 0.90, in: rect),
            controlPoint2: statusLetterPoint(x: 0.82, y: 0.86, in: rect)
        )
        path.curve(
            to: statusLetterPoint(x: 0.22, y: 0.52, in: rect),
            controlPoint1: statusLetterPoint(x: 0.82, y: 0.54, in: rect),
            controlPoint2: statusLetterPoint(x: 0.58, y: 0.52, in: rect)
        )

        path.move(to: statusLetterPoint(x: 0.22, y: 0.52, in: rect))
        path.curve(
            to: statusLetterPoint(x: 0.76, y: 0.32, in: rect),
            controlPoint1: statusLetterPoint(x: 0.62, y: 0.54, in: rect),
            controlPoint2: statusLetterPoint(x: 0.88, y: 0.48, in: rect)
        )
        path.curve(
            to: statusLetterPoint(x: 0.22, y: 0.12, in: rect),
            controlPoint1: statusLetterPoint(x: 0.88, y: 0.14, in: rect),
            controlPoint2: statusLetterPoint(x: 0.62, y: 0.10, in: rect)
        )
        return path
    }

    private static func statusLetterPoint(x: CGFloat, y: CGFloat, in rect: NSRect) -> NSPoint {
        NSPoint(
            x: rect.minX + rect.width * x,
            y: rect.minY + rect.height * y
        )
    }

    private static func menuStatusLight(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = drawingImage(size: size) { bounds in
            let circleRect = NSRect(
                x: bounds.midX - 4,
                y: bounds.midY - 4,
                width: 8,
                height: 8
            )
            let circle = NSBezierPath(ovalIn: circleRect)
            color.setFill()
            circle.fill()

            NSColor.white.withAlphaComponent(0.9).setStroke()
            circle.lineWidth = 1
            circle.stroke()
        }
        image.isTemplate = false
        return image
    }

    private static func drawingImage(size: NSSize, drawing: @escaping (NSRect) -> Void) -> NSImage {
        let image = NSImage(size: size, flipped: false) { bounds in
            drawing(bounds)
            return true
        }
        image.cacheMode = .never
        return image
    }
}
