import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let state = AppState()
        appState = state
        statusItemController = StatusItemController(appState: state)
        state.start()
    }
}

@main
@MainActor
struct turnintoserverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class StatusItemController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
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
        Publishers.CombineLatest3(
            appState.$serverModeActive,
            appState.$allowBatteryServerMode,
            appState.$isCommandRunning
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
        serverModeItem.image = NSImage(
            systemSymbolName: appState.serverModeActionSystemImage,
            accessibilityDescription: nil
        )
        serverModeItem.isEnabled = !appState.isCommandRunning
        menu.addItem(serverModeItem)

        let statusItem = NSMenuItem(title: appState.statusSummaryDisplay, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(.separator())

        let batteryItem = NSMenuItem(
            title: AppText.allowBatteryServerMode,
            action: #selector(toggleBatteryServerMode),
            keyEquivalent: ""
        )
        batteryItem.target = self
        batteryItem.state = appState.allowBatteryServerMode ? .on : .off
        batteryItem.isEnabled = !appState.isCommandRunning
        menu.addItem(batteryItem)

        let launchItem = NSMenuItem(
            title: AppText.launchAtLogin,
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = appState.launchAtLoginEnabled ? .on : .off
        launchItem.isEnabled = !appState.isLaunchAtLoginChanging
        menu.addItem(launchItem)

        menu.addItem(.separator())

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

    @objc private func toggleBatteryServerMode() {
        appState.setAllowBatteryServerMode(!appState.allowBatteryServerMode)
    }

    @objc private func toggleLaunchAtLogin() {
        appState.setLaunchAtLoginEnabled(!appState.launchAtLoginEnabled)
    }

    @objc private func quit() {
        Task { @MainActor in
            if await appState.prepareForQuit() {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

private enum MenuBarStatusIconRenderer {
    static func image(for style: MenuBarIconStyle) -> NSImage? {
        switch style {
        case .idle:
            let image = (NSImage(named: "MenuBarIcon") ?? NSImage(
                systemSymbolName: "server.rack",
                accessibilityDescription: nil
            ))?.copy() as? NSImage
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = true
            return image
        case .serverModePowerOnly:
            return statusDot(color: .systemGreen, text: "S")
        case .serverModeBatteryAllowed:
            return statusDot(color: .systemRed, text: "B")
        }
    }

    static func title(for style: MenuBarIconStyle) -> String {
        switch style {
        case .idle:
            return ""
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
