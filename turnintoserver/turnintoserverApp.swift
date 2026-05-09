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

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        observeAppState()
        updateStatusButton()
        rebuildMenu()
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
    }

    func menuWillOpen(_ menu: NSMenu) {
        appState.refreshLaunchAtLoginStatus()
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let serverModeItem = NSMenuItem(
            title: appState.serverModeActionTitle,
            action: #selector(toggleServerMode),
            keyEquivalent: ""
        )
        serverModeItem.target = self
        serverModeItem.image = MenuBarStatusIconRenderer.systemImage(
            named: appState.serverModeActionSystemImage
        )
        serverModeItem.isEnabled = !appState.isCommandRunning
        menu.addItem(serverModeItem)

        let statusItem = NSMenuItem(title: appState.statusSummaryDisplay, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        if let runtimeDisplay = appState.serverModeRuntimeDisplay {
            let runtimeItem = NSMenuItem(title: runtimeDisplay, action: nil, keyEquivalent: "")
            runtimeItem.isEnabled = false
            menu.addItem(runtimeItem)
        }

        menu.addItem(.separator())

        let batteryItem = NSMenuItem()
        batteryItem.view = MenuToggleRowView(
            title: AppText.allowBatteryServerMode,
            isOn: appState.allowBatteryServerMode,
            isToggleEnabled: !appState.isCommandRunning,
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

    @objc private func toggleServerMode() {
        Task { @MainActor in
            await appState.toggleServerMode()
        }
    }

    @objc private func toggleBatteryServerMode(_ sender: Any?) {
        appState.toggleBatteryServerMode()
        menu.cancelTracking()
    }

    @objc private func toggleLowBatteryNotifications(_ sender: Any?) {
        appState.toggleLowBatteryNotifications()
        menu.cancelTracking()
    }

    @objc private func toggleHotKeys(_ sender: Any?) {
        appState.toggleHotKeysEnabled()
        menu.cancelTracking()
    }

    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        appState.setLaunchAtLoginEnabled(!appState.launchAtLoginEnabled)
        menu.cancelTracking()
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

private final class MenuToggleRowView: NSView {
    init(
        title: String,
        isOn: Bool,
        isToggleEnabled: Bool,
        tooltip: String? = nil,
        settingsButtonTitle: String? = nil,
        target: AnyObject,
        toggleAction: Selector,
        settingsAction: Selector? = nil
    ) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 30))

        let checkmarkLabel = NSTextField(labelWithString: isOn ? "✓" : "")
        checkmarkLabel.alignment = .center
        checkmarkLabel.font = NSFont.menuFont(ofSize: 0)
        checkmarkLabel.textColor = isToggleEnabled ? .labelColor : .disabledControlTextColor
        checkmarkLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.menuFont(ofSize: 0)
        titleLabel.textColor = isToggleEnabled ? .labelColor : .disabledControlTextColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let toggleOverlayButton = NSButton()
        toggleOverlayButton.isBordered = false
        toggleOverlayButton.isTransparent = true
        toggleOverlayButton.title = ""
        toggleOverlayButton.target = target
        toggleOverlayButton.action = toggleAction
        toggleOverlayButton.isEnabled = isToggleEnabled
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
        addSubview(toggleOverlayButton)
        if let settingsButton {
            addSubview(settingsButton)
        }

        var constraints: [NSLayoutConstraint] = [
            heightAnchor.constraint(equalToConstant: 30),
            widthAnchor.constraint(equalToConstant: 280),

            checkmarkLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            checkmarkLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkmarkLabel.widthAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 46),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            toggleOverlayButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            toggleOverlayButton.topAnchor.constraint(equalTo: topAnchor),
            toggleOverlayButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]

        if let settingsButton {
            constraints += [
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: settingsButton.leadingAnchor, constant: -8),
                toggleOverlayButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -6),
                settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                settingsButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                settingsButton.widthAnchor.constraint(equalToConstant: 64)
            ]
        } else {
            constraints += [
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
                toggleOverlayButton.trailingAnchor.constraint(equalTo: trailingAnchor)
            ]
        }

        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }
}

private enum MenuBarStatusIconRenderer {
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
}
