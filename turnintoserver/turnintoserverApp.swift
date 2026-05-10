import AppKit
import Combine

@main
enum TurnIntoServerMain {
    @MainActor
    static func main() {
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
        state.start()
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
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
}

@MainActor
private final class StatusItemController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var aboutWindowController: AboutWindowController?
    private var lowBatterySettingsWindowController: LowBatterySettingsWindowController?
    private var shortcutSettingsWindowController: ShortcutSettingsWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var isMenuOpen = false

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
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

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        appState.refreshLaunchAtLoginStatus()
        rebuildMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let serverModeItem = NSMenuItem()
        serverModeItem.view = MenuActionRowView(
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
        menu.addItem(serverModeItem)

        let statusItem = NSMenuItem()
        statusItem.view = MenuTextRowView(title: appState.statusSummaryDisplay)
        menu.addItem(statusItem)

        if let runtimeDisplay = appState.serverModeRuntimeDisplay {
            let runtimeItem = NSMenuItem()
            runtimeItem.view = MenuTextRowView(title: runtimeDisplay)
            menu.addItem(runtimeItem)
        }

        menu.addItem(.separator())

        let batteryItem = NSMenuItem()
        batteryItem.view = MenuToggleRowView(
            title: AppText.allowBatteryServerMode,
            isOn: appState.allowBatteryServerMode,
            isToggleEnabled: !appState.isCommandRunning,
            shortcutTitle: batteryModeShortcutDisplay,
            target: self,
            toggleAction: #selector(toggleBatteryServerMode(_:))
        )
        menu.addItem(batteryItem)

        let lowBatteryItem = NSMenuItem()
        lowBatteryItem.view = MenuToggleRowView(
            title: AppText.lowBatteryNotifications,
            isOn: appState.lowBatteryNotificationsEnabled,
            isToggleEnabled: appState.lowBatteryNotificationsEnabled
                || AppState.canEnableLowBatteryNotifications(),
            tooltip: AppText.lowBatteryNotificationsRequireTest,
            settingsButtonTitle: AppText.configureLowBatteryNotifications,
            target: self,
            toggleAction: #selector(toggleLowBatteryNotifications(_:)),
            settingsAction: #selector(showLowBatterySettings(_:))
        )
        menu.addItem(lowBatteryItem)

        let shortcutsItem = NSMenuItem()
        shortcutsItem.view = MenuToggleRowView(
            title: AppText.enableShortcuts,
            isOn: appState.hotKeysEnabled,
            isToggleEnabled: true,
            settingsButtonTitle: AppText.configureShortcuts,
            target: self,
            toggleAction: #selector(toggleHotKeys(_:)),
            settingsAction: #selector(showShortcutSettings(_:))
        )
        menu.addItem(shortcutsItem)

        let launchAtLoginItem = NSMenuItem()
        launchAtLoginItem.view = MenuToggleRowView(
            title: AppText.launchAtLogin,
            isOn: appState.launchAtLoginEnabled,
            isToggleEnabled: appState.launchAtLoginSupported && !appState.isLaunchAtLoginChanging,
            tooltip: appState.launchAtLoginSupported ? nil : AppText.launchAtLoginUnsupported,
            target: self,
            toggleAction: #selector(toggleLaunchAtLogin(_:))
        )
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: AppText.aboutApplication, action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: AppText.quit, action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        quitItem.isEnabled = !appState.isCommandRunning
        menu.addItem(quitItem)
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        let style = appState.menuBarIconStyle
        button.image = MenuBarStatusIconRenderer.image(for: style)
        button.title = MenuBarStatusIconRenderer.title(for: style)
        button.toolTip = appState.menuBarStatusTitle
    }

    private func refreshMenuIfOpen() {
        guard isMenuOpen else {
            return
        }

        rebuildMenu()
    }

    private func refreshMenuSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshMenuIfOpen()
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
        Task { @MainActor in
            if await appState.prepareForQuit() {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

private enum MenuRowMetric {
    static let width: CGFloat = 250
    static let height: CGFloat = 30
    static let textHeight: CGFloat = 26
    static let indicatorLeading: CGFloat = 8
    static let indicatorWidth: CGFloat = 18
    static let titleLeading: CGFloat = 34
    static let trailing: CGFloat = 10
    static let shortcutTrailing: CGFloat = 12
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

    override var acceptsFirstResponder: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        rowView?.setPressed(true)
        super.mouseDown(with: event)
        rowView?.setPressed(false)
    }
}

private final class MenuActionRowView: HighlightedMenuRowView {
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")

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

        let actionButton = MenuRowButton()
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

    override fileprivate func applyHighlightAppearance(isHighlighted: Bool) {
        let color = contentTextColor(isHighlighted: isHighlighted)
        titleLabel.textColor = color
        imageView.contentTintColor = color
        shortcutLabel.textColor = isHighlighted ? color : .tertiaryLabelColor
        imageView.alphaValue = isRowEnabled ? 1 : 0.45
    }
}

private final class MenuTextRowView: NSView {
    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuRowMetric.width, height: MenuRowMetric.textHeight))

        let titleLabel = NSTextField(labelWithString: title)
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

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }
}

private final class MenuToggleRowView: HighlightedMenuRowView {
    private let checkmarkLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")

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

        let shortcutLabel = NSTextField(labelWithString: shortcutTitle ?? "")
        shortcutLabel.font = NSFont.menuFont(ofSize: 0)
        shortcutLabel.textColor = .tertiaryLabelColor
        shortcutLabel.lineBreakMode = .byTruncatingTail
        shortcutLabel.alignment = .right
        shortcutLabel.isHidden = shortcutTitle == nil
        shortcutLabel.setContentHuggingPriority(.required, for: .horizontal)
        shortcutLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        let toggleOverlayButton = MenuRowButton()
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
            return "ON"
        case .serverModePowerOnly:
            return "ON"
        case .serverModeBatteryAllowed:
            return "BAT"
        }
    }

    private static func statusDot(color: NSColor, text: String) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()

        let circleRect = NSRect(x: 1.5, y: 1.5, width: 15, height: 15)
        let circle = NSBezierPath(ovalIn: circleRect)
        color.setFill()
        circle.fill()

        NSColor.white.withAlphaComponent(0.95).setStroke()
        circle.lineWidth = 1
        circle.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2 - 0.5,
            width: textSize.width,
            height: textSize.height
        )
        attributedText.draw(in: textRect)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func menuStatusLight(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()

        let circleRect = NSRect(x: 5, y: 5, width: 8, height: 8)
        let circle = NSBezierPath(ovalIn: circleRect)
        color.setFill()
        circle.fill()

        NSColor.white.withAlphaComponent(0.9).setStroke()
        circle.lineWidth = 1
        circle.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
