import AppKit
import Carbon
import Foundation
import SwiftUI

@MainActor
final class AboutWindowController: NSWindowController {
    init(appState: AppState) {
        let hostingController = NSHostingController(rootView: AboutView(appState: appState))
        let window = NSWindow(contentViewController: hostingController)
        window.title = AppText.aboutApplication
        window.styleMask = [.titled, .closable]
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 500, height: 420)
        window.contentMaxSize = NSSize(width: 500, height: 420)
        window.setContentSize(NSSize(width: 500, height: 420))
        Self.configureCenteredTitle(for: window)
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private static func configureCenteredTitle(for window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let titlebarView = closeButton.superview else {
            return
        }

        let titleLabel = NSTextField(labelWithString: AppText.aboutApplication)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        titlebarView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: titlebarView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titlebarView.leadingAnchor, constant: 90),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titlebarView.trailingAnchor, constant: -90)
        ])
    }
}

@MainActor
final class LowBatterySettingsWindowController: NSWindowController {
    init(appState: AppState) {
        let hostingController = NSHostingController(rootView: LowBatteryNotificationSettingsView(appState: appState))
        let window = NSWindow(contentViewController: hostingController)
        window.title = AppText.iMessageSettingsTitle
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 520, height: 230)
        window.contentMaxSize = NSSize(width: 520, height: 230)
        window.setContentSize(NSSize(width: 520, height: 230))
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class ShortcutSettingsWindowController: NSWindowController {
    init() {
        let hostingController = NSHostingController(rootView: ShortcutSettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = AppText.shortcutHintsTitle
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 460, height: 160)
        window.contentMaxSize = NSSize(width: 460, height: 160)
        window.setContentSize(NSSize(width: 460, height: 160))
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class TimedServerModeSettingsWindowController: NSWindowController {
    init(appState: AppState) {
        let hostingController = NSHostingController(rootView: TimedServerModeSettingsView(appState: appState))
        let window = NSWindow(contentViewController: hostingController)
        window.title = AppText.timedServerModeSettingsTitle
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 360, height: 360)
        window.contentMaxSize = NSSize(width: 360, height: 360)
        window.setContentSize(NSSize(width: 360, height: 360))
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct AboutView: View {
    @ObservedObject private var updateModel: PreferencesUpdateViewModel

    @MainActor
    init(appState: AppState) {
        updateModel = PreferencesUpdateViewModel(appState: appState)
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 2)
            header
            updateSection
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 36, leading: 34, bottom: 28, trailing: 34))
        .frame(width: 500, height: 420)
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 92, height: 92)
                .cornerRadius(22)
                .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 3)

            VStack(spacing: 4) {
                Text("turnintoserver")
                    .font(.system(size: 28, weight: .bold))
                Text(AppText.currentVersion(PreferencesUpdateViewModel.currentVersionDisplay))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(spacing: 7) {
                Text(AppText.developer("qianyushi"))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(AppText.githubPrefix)
                    Button(AppText.githubURLDisplay) {
                        PreferencesUpdateViewModel.openGitHub()
                    }
                    .buttonStyle(.link)
                }
            }
            .font(.system(size: 13))
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var updateSection: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.horizontal, 10)

            HStack(spacing: 10) {
                Spacer()

                Button(AppText.checkForUpdates) {
                    updateModel.checkForUpdates()
                }
                .disabled(updateModel.isChecking || updateModel.isDownloading)

                if updateModel.canRestartToInstall {
                    Button(AppText.restartToInstallUpdate) {
                        updateModel.restartAndInstall()
                    }
                }

                Spacer()
            }

            if updateModel.isDownloading {
                LinearProgressIndicator(value: updateModel.downloadProgress)
                    .frame(width: 280)
                    .frame(height: 8)
            }

            Text(updateModel.statusText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

struct TimedServerModeSettingsView: View {
    @ObservedObject private var appState: AppState
    @ObservedObject private var settingsModel: TimedServerModeSettingsViewModel

    @MainActor
    init(appState: AppState) {
        self.appState = appState
        settingsModel = TimedServerModeSettingsViewModel(appState: appState)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(appState.timedServerModeDurationOptions.enumerated()), id: \.element) { index, duration in
                        TimedServerModeDurationRow(
                            title: AppText.timedServerModeDuration(minutes: duration),
                            isSelected: settingsModel.selectedDurationMinutes == duration,
                            usesAlternateBackground: index.isMultiple(of: 2)
                        ) {
                            settingsModel.selectDuration(duration)
                        }
                    }
                }
                .padding(EdgeInsets(top: 16, leading: 10, bottom: 16, trailing: 10))
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Button(AppText.resetTimedServerModeDurations) {
                        settingsModel.resetDurations()
                    }

                    Spacer()

                    HStack(spacing: 0) {
                        Button("−") {
                            settingsModel.removeSelectedDuration()
                        }
                        .disabled(!settingsModel.canRemoveSelectedDuration)
                        .frame(width: 36)

                        Divider()
                            .frame(height: 18)

                        Button("+") {
                            settingsModel.addDuration()
                        }
                        .frame(width: 36)
                    }
                }
            }
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 16, trailing: 20))
        }
        .frame(width: 360, height: 360, alignment: .topLeading)
    }
}

private struct TimedServerModeDurationRow: View {
    let title: String
    let isSelected: Bool
    var usesAlternateBackground = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 30)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }

        if usesAlternateBackground {
            return Color.secondary.opacity(0.08)
        }

        return Color.clear
    }
}

struct LowBatteryNotificationSettingsView: View {
    @ObservedObject private var appState: AppState
    @ObservedObject private var notificationModel: NotificationSettingsViewModel

    @MainActor
    init(appState: AppState) {
        self.appState = appState
        notificationModel = NotificationSettingsViewModel()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            notificationChannelRow(
                title: AppText.iMessageChannelTitle,
                infoTitle: AppText.iMessageInfoTitle,
                infoMessage: AppText.iMessageInfoMessage,
                placeholder: AppText.iMessageRecipientPlaceholder,
                text: $notificationModel.iMessageRecipientAddress,
                isTesting: notificationModel.isSendingIMessageTest,
                statusText: notificationModel.iMessageStatusText
            ) {
                notificationModel.sendIMessageTest()
            }

            Divider()

            notificationChannelRow(
                title: AppText.barkChannelTitle,
                infoTitle: AppText.barkInfoTitle,
                infoMessage: AppText.barkInfoMessage,
                placeholder: AppText.barkPushEndpointPlaceholder,
                text: $notificationModel.barkPushEndpoint,
                isTesting: notificationModel.isSendingBarkTest,
                statusText: notificationModel.barkStatusText
            ) {
                notificationModel.sendBarkTest()
            }
        }
        .padding(EdgeInsets(top: 22, leading: 24, bottom: 20, trailing: 24))
        .frame(width: 520, height: 230, alignment: .topLeading)
        .onReceive(notificationModel.$canEnableLowBatteryNotifications) { canEnable in
            if !canEnable, appState.lowBatteryNotificationsEnabled {
                appState.setLowBatteryNotificationsEnabled(false)
            }
        }
    }

    private func notificationChannelRow(
        title: String,
        infoTitle: String,
        infoMessage: String,
        placeholder: String,
        text: Binding<String>,
        isTesting: Bool,
        statusText: String,
        onTest: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                InfoCircleButton {
                    showInfo(title: infoTitle, message: infoMessage)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                TextField(placeholder, text: text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button(AppText.testNotificationChannel) {
                    onTest()
                }
                .disabled(isTesting)
            }

            if !statusText.isEmpty {
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func showInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: AppText.ok)
        alert.runModal()
    }
}

private struct InfoCircleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.75), lineWidth: 1)
                Text("i")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .frame(width: 15, height: 15)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject private var shortcutModel: ShortcutSettingsViewModel

    @MainActor
    init() {
        shortcutModel = ShortcutSettingsViewModel()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppText.shortcutHintsTitle)
                .font(.system(size: 13, weight: .semibold))

            ShortcutRow(
                title: AppText.serverModeShortcutLabel,
                shortcut: shortcutModel.serverModeShortcut,
                isRecording: shortcutModel.recordingTarget == .serverMode
            ) {
                shortcutModel.record(.serverMode)
            }

            ShortcutRow(
                title: AppText.batteryModeShortcutLabel,
                shortcut: shortcutModel.batteryModeShortcut,
                isRecording: shortcutModel.recordingTarget == .batteryMode
            ) {
                shortcutModel.record(.batteryMode)
            }

            HStack(spacing: 10) {
                Button(AppText.resetShortcuts) {
                    shortcutModel.resetShortcuts()
                }

                Spacer()
            }
        }
        .padding(16)
        .frame(width: 460, height: 160, alignment: .topLeading)
    }
}

private struct ShortcutRow: View {
    let title: String
    let shortcut: HotKeyShortcut?
    let isRecording: Bool
    let onRecord: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 150, alignment: .leading)

            Text(isRecording ? AppText.recordingShortcut : shortcutDisplayText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(shortcut == nil && !isRecording ? .secondary : .primary)
                .frame(width: 120, alignment: .leading)

            Button(AppText.recordShortcut) {
                onRecord()
            }
            .disabled(isRecording)

            Spacer()
        }
    }

    private var shortcutDisplayText: String {
        shortcut?.displayString ?? AppText.shortcutNotSet
    }
}

private struct LinearProgressIndicator: NSViewRepresentable {
    let value: Double

    func makeNSView(context: Context) -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.isIndeterminate = false
        indicator.style = .bar
        indicator.minValue = 0
        indicator.maxValue = 1
        indicator.doubleValue = 0
        indicator.controlSize = .small
        return indicator
    }

    func updateNSView(_ nsView: NSProgressIndicator, context: Context) {
        nsView.doubleValue = max(0, min(1, value))
    }
}

@MainActor
private final class TimedServerModeSettingsViewModel: ObservableObject {
    @Published var selectedDurationMinutes: Int?

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        selectedDurationMinutes = nil
    }

    var canRemoveSelectedDuration: Bool {
        guard let selectedDurationMinutes else {
            return false
        }

        return appState.timedServerModeDurationOptions.contains(selectedDurationMinutes)
            && appState.timedServerModeDurationOptions.count > 1
    }

    func selectDuration(_ durationMinutes: Int?) {
        selectedDurationMinutes = durationMinutes
    }

    func removeSelectedDuration() {
        guard let selectedDurationMinutes else {
            return
        }

        appState.removeTimedServerModeDuration(minutes: selectedDurationMinutes)

        if appState.timedServerModeDurationOptions.contains(selectedDurationMinutes) {
            self.selectedDurationMinutes = selectedDurationMinutes
        } else {
            self.selectedDurationMinutes = nil
        }
    }

    func resetDurations() {
        appState.resetTimedServerModeDurations()
        selectedDurationMinutes = nil
    }

    func addDuration() {
        guard let durationMinutes = Self.requestDurationMinutes(),
              let addedDuration = appState.addTimedServerModeDuration(minutes: durationMinutes) else {
            return
        }

        selectedDurationMinutes = addedDuration
    }

    private static func requestDurationMinutes() -> Int? {
        while true {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = AppText.addTimedServerModeDurationTitle
            alert.informativeText = AppText.addTimedServerModeDurationMessage
            alert.addButton(withTitle: AppText.addTimedServerModeDurationConfirm)
            alert.addButton(withTitle: AppText.cancel)

            let hoursField = makeDurationInputField()
            hoursField.placeholderString = "0"

            let minutesField = makeDurationInputField()
            minutesField.placeholderString = "0"

            let hoursLabel = NSTextField(labelWithString: AppText.timedServerModeHoursUnit)
            let minutesLabel = NSTextField(labelWithString: AppText.timedServerModeMinutesUnit)

            let stackView = NSStackView(views: [
                hoursField,
                hoursLabel,
                minutesField,
                minutesLabel
            ])
            stackView.orientation = .horizontal
            stackView.alignment = .centerY
            stackView.spacing = 8
            stackView.translatesAutoresizingMaskIntoConstraints = false

            let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 34))
            accessoryView.addSubview(stackView)
            NSLayoutConstraint.activate([
                stackView.centerXAnchor.constraint(equalTo: accessoryView.centerXAnchor),
                stackView.centerYAnchor.constraint(equalTo: accessoryView.centerYAnchor)
            ])
            alert.accessoryView = accessoryView
            alert.window.initialFirstResponder = hoursField

            guard alert.runModal() == .alertFirstButtonReturn else {
                return nil
            }

            if let durationMinutes = parsedDurationMinutes(
                hours: hoursField.stringValue,
                minutes: minutesField.stringValue
            ) {
                return durationMinutes
            }

            let invalidAlert = NSAlert()
            invalidAlert.alertStyle = .warning
            invalidAlert.messageText = AppText.invalidTimedServerModeDurationComponents
            invalidAlert.addButton(withTitle: AppText.ok)
            invalidAlert.runModal()
        }
    }

    private static func makeDurationInputField() -> NSTextField {
        let field = NSTextField(frame: .zero)
        field.alignment = .right
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.isBezeled = true
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.focusRingType = .default
        field.usesSingleLineMode = true
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.widthAnchor.constraint(equalToConstant: 76),
            field.heightAnchor.constraint(equalToConstant: 28)
        ])
        return field
    }

    private static func parsedDurationMinutes(hours: String, minutes: String) -> Int? {
        let trimmedHours = hours.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMinutes = minutes.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let hourValue = trimmedHours.isEmpty ? 0 : Int(trimmedHours),
              let minuteValue = trimmedMinutes.isEmpty ? 0 : Int(trimmedMinutes),
              hourValue >= 0,
              minuteValue >= 0,
              minuteValue < 60 else {
            return nil
        }

        let totalMinutes = hourValue * 60 + minuteValue
        return AppState.normalizedTimedServerModeDuration(totalMinutes)
    }
}

@MainActor
private final class NotificationSettingsViewModel: ObservableObject {
    @Published var iMessageRecipientAddress: String {
        didSet {
            let trimmedValue = iMessageRecipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(iMessageRecipientAddress, forKey: AppDefaultsKey.iMessageRecipientAddress)
            if trimmedValue != verifiedIMessageRecipientAddress {
                iMessageStatusText = trimmedValue.isEmpty ? "" : AppText.iMessageNeedsRetest
            }
            refreshReadiness()
        }
    }
    @Published var barkPushEndpoint: String {
        didSet {
            let trimmedValue = barkPushEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(barkPushEndpoint, forKey: AppDefaultsKey.barkPushEndpoint)
            if trimmedValue != verifiedBarkPushEndpoint {
                barkStatusText = trimmedValue.isEmpty ? "" : AppText.barkNeedsRetest
            }
            refreshReadiness()
        }
    }
    @Published var isSendingIMessageTest = false
    @Published var isSendingBarkTest = false
    @Published var iMessageStatusText = ""
    @Published var barkStatusText = ""
    @Published private(set) var canEnableLowBatteryNotifications = false

    private let defaults: UserDefaults
    private var verifiedIMessageRecipientAddress = ""
    private var verifiedBarkPushEndpoint = ""

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        iMessageRecipientAddress = defaults.string(forKey: AppDefaultsKey.iMessageRecipientAddress) ?? ""
        barkPushEndpoint = defaults.string(forKey: AppDefaultsKey.barkPushEndpoint) ?? ""
        verifiedIMessageRecipientAddress = defaults.string(forKey: AppDefaultsKey.verifiedIMessageRecipientAddress)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        verifiedBarkPushEndpoint = defaults.string(forKey: AppDefaultsKey.verifiedBarkPushEndpoint)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        refreshReadiness()
        refreshStatusTexts()
    }

    func sendIMessageTest() {
        Task {
            await sendIMessageTestAsync()
        }
    }

    func sendBarkTest() {
        Task {
            await sendBarkTestAsync()
        }
    }

    private func sendIMessageTestAsync() async {
        guard !isSendingIMessageTest else {
            return
        }

        let recipient = iMessageRecipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipient.isEmpty else {
            iMessageStatusText = AppText.iMessageRecipientMissing
            return
        }

        isSendingIMessageTest = true
        iMessageStatusText = AppText.iMessageTestSending

        defer {
            isSendingIMessageTest = false
        }

        do {
            try await IMessageNotifier.send(
                message: AppText.iMessageTestMessage(macName: IMessageNotifier.defaultMacName),
                to: recipient
            )
            verifiedIMessageRecipientAddress = recipient
            defaults.set(recipient, forKey: AppDefaultsKey.verifiedIMessageRecipientAddress)
            refreshReadiness()
            iMessageStatusText = AppText.iMessageTestSent
        } catch {
            iMessageStatusText = AppText.iMessageTestFailed(error.localizedDescription)
        }
    }

    private func sendBarkTestAsync() async {
        guard !isSendingBarkTest else {
            return
        }

        let endpoint = barkPushEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else {
            barkStatusText = AppText.barkEndpointMissing
            return
        }

        isSendingBarkTest = true
        barkStatusText = AppText.barkTestSending

        defer {
            isSendingBarkTest = false
        }

        do {
            try await BarkNotifier.send(
                title: "turnintoserver",
                body: AppText.barkTestBody(macName: IMessageNotifier.defaultMacName),
                endpoint: endpoint
            )
            verifiedBarkPushEndpoint = endpoint
            defaults.set(endpoint, forKey: AppDefaultsKey.verifiedBarkPushEndpoint)
            refreshReadiness()
            barkStatusText = AppText.barkTestSent
        } catch {
            barkStatusText = AppText.barkTestFailed(error.localizedDescription)
        }
    }

    private func refreshReadiness() {
        canEnableLowBatteryNotifications = AppState.canEnableLowBatteryNotifications(defaults: defaults)
    }

    private func refreshStatusTexts() {
        let recipient = iMessageRecipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !recipient.isEmpty, recipient != verifiedIMessageRecipientAddress {
            iMessageStatusText = AppText.iMessageNeedsRetest
        }

        let endpoint = barkPushEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !endpoint.isEmpty, endpoint != verifiedBarkPushEndpoint {
            barkStatusText = AppText.barkNeedsRetest
        }
    }
}

@MainActor
private final class ShortcutSettingsViewModel: ObservableObject {
    enum Target {
        case serverMode
        case batteryMode
    }

    @Published var serverModeShortcut: HotKeyShortcut?
    @Published var batteryModeShortcut: HotKeyShortcut?
    @Published var recordingTarget: Target?
    @Published var statusText = AppText.shortcutRecordHint

    private var keyEventMonitor: Any?
    private var localMouseEventMonitor: Any?
    private var globalMouseEventMonitor: Any?

    init() {
        serverModeShortcut = HotKeyShortcut.loadOptional(
            defaultsKey: AppDefaultsKey.serverModeHotKey,
            disabledDefaultsKey: AppDefaultsKey.serverModeHotKeyDisabled,
            default: .defaultServerMode
        )
        batteryModeShortcut = HotKeyShortcut.loadOptional(
            defaultsKey: AppDefaultsKey.batteryModeHotKey,
            disabledDefaultsKey: AppDefaultsKey.batteryModeHotKeyDisabled,
            default: .defaultBatteryMode
        )
    }

    deinit {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
        }
        if let localMouseEventMonitor {
            NSEvent.removeMonitor(localMouseEventMonitor)
        }
        if let globalMouseEventMonitor {
            NSEvent.removeMonitor(globalMouseEventMonitor)
        }
        NotificationCenter.default.post(name: .turnIntoServerHotKeyRecordingDidEnd, object: nil)
    }

    func record(_ target: Target) {
        stopRecording()
        recordingTarget = target
        statusText = AppText.recordingShortcut
        NotificationCenter.default.post(name: .turnIntoServerHotKeyRecordingDidStart, object: nil)
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return nil
        }
        localMouseEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.clearRecordingShortcut()
            return event
        }
        globalMouseEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clearRecordingShortcut()
            }
        }
    }

    func resetShortcuts() {
        stopRecording()
        HotKeyShortcut.reset()
        serverModeShortcut = .defaultServerMode
        batteryModeShortcut = .defaultBatteryMode
        statusText = AppText.shortcutRecordHint
    }

    private func clearShortcut(_ target: Target) {
        stopRecording()

        switch target {
        case .serverMode:
            HotKeyShortcut.clear(
                defaultsKey: AppDefaultsKey.serverModeHotKey,
                disabledDefaultsKey: AppDefaultsKey.serverModeHotKeyDisabled
            )
            serverModeShortcut = nil
        case .batteryMode:
            HotKeyShortcut.clear(
                defaultsKey: AppDefaultsKey.batteryModeHotKey,
                disabledDefaultsKey: AppDefaultsKey.batteryModeHotKeyDisabled
            )
            batteryModeShortcut = nil
        }

        statusText = AppText.shortcutRecordHint
    }

    private func clearRecordingShortcut() {
        guard let recordingTarget else {
            return
        }

        clearShortcut(recordingTarget)
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard event.keyCode != UInt16(kVK_Escape) else {
            stopRecording()
            statusText = AppText.shortcutRecordHint
            return
        }

        guard let shortcut = HotKeyShortcut(event: event) else {
            statusText = AppText.shortcutRecordHint
            return
        }

        switch recordingTarget {
        case .serverMode:
            shortcut.save(
                defaultsKey: AppDefaultsKey.serverModeHotKey,
                disabledDefaultsKey: AppDefaultsKey.serverModeHotKeyDisabled
            )
            serverModeShortcut = shortcut
        case .batteryMode:
            shortcut.save(
                defaultsKey: AppDefaultsKey.batteryModeHotKey,
                disabledDefaultsKey: AppDefaultsKey.batteryModeHotKeyDisabled
            )
            batteryModeShortcut = shortcut
        case .none:
            break
        }

        stopRecording()
        statusText = AppText.shortcutRecordHint
    }

    private func stopRecording() {
        removeEventMonitors()

        if recordingTarget != nil {
            recordingTarget = nil
            NotificationCenter.default.post(name: .turnIntoServerHotKeyRecordingDidEnd, object: nil)
        }
    }

    private func removeEventMonitors() {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
        if let localMouseEventMonitor {
            NSEvent.removeMonitor(localMouseEventMonitor)
            self.localMouseEventMonitor = nil
        }
        if let globalMouseEventMonitor {
            NSEvent.removeMonitor(globalMouseEventMonitor)
            self.globalMouseEventMonitor = nil
        }
    }
}

@MainActor
private final class PreferencesUpdateViewModel: ObservableObject {
    struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL
        let assets: [GitHubAsset]

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: URL

        private enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    static let githubURL = URL(string: "https://github.com/QianYushi/turnintoserver")!

    static var currentVersionDisplay: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? AppText.unknownVersion
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        guard let build, !build.isEmpty else {
            return version
        }

        return "\(version) (\(build))"
    }

    @Published var isChecking = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var statusText = AppText.updateIdle
    @Published var canRestartToInstall = false

    private var preparedDMGURL: URL?
    private var progressObservation: NSKeyValueObservation?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    static func openGitHub() {
        NSWorkspace.shared.open(githubURL)
    }

    func checkForUpdates() {
        Task {
            await checkForUpdatesAsync()
        }
    }

    func restartAndInstall() {
        Task {
            await restartAndInstallAsync()
        }
    }

    private func checkForUpdatesAsync() async {
        guard !isChecking, !isDownloading else {
            return
        }

        isChecking = true
        canRestartToInstall = false
        preparedDMGURL = nil
        downloadProgress = 0
        statusText = AppText.checkingForUpdates

        defer {
            isChecking = false
        }

        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/QianYushi/turnintoserver/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("turnintoserver", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await Self.fetchData(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                statusText = AppText.updateCheckFailed(AppText.updateServerUnavailable)
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

            guard Self.isVersion(release.tagName, newerThan: currentVersion) else {
                statusText = AppText.alreadyUpToDate
                return
            }

            guard let dmgAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else {
                statusText = AppText.noDMGFound(release.tagName)
                return
            }

            statusText = AppText.updateAvailable(release.tagName)
            try await downloadUpdate(from: dmgAsset.browserDownloadURL, tagName: release.tagName)
        } catch {
            statusText = AppText.updateCheckFailed(error.localizedDescription)
        }
    }

    private func downloadUpdate(from url: URL, tagName: String) async throws {
        isDownloading = true
        downloadProgress = 0
        statusText = AppText.downloadingLatestDMG

        defer {
            isDownloading = false
            progressObservation = nil
        }

        let (data, response) = try await fetchDataWithProgress(for: URLRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            statusText = AppText.downloadFailed(AppText.updateServerUnavailable)
            return
        }

        let destination = try Self.temporaryDMGDestination(tagName: tagName)
        try data.write(to: destination, options: .atomic)
        preparedDMGURL = destination
        downloadProgress = 1
        canRestartToInstall = true
        statusText = AppText.updateReadyToRestart
    }

    private func restartAndInstallAsync() async {
        guard let preparedDMGURL else {
            return
        }

        statusText = AppText.restartingToInstallUpdate

        guard await appState.prepareForQuit() else {
            statusText = AppText.updateInstallCancelled
            return
        }

        do {
            try Self.launchInstaller(dmgURL: preparedDMGURL, targetAppURL: Bundle.main.bundleURL)
            NSApplication.shared.terminate(nil)
        } catch {
            statusText = AppText.updateInstallFailed(error.localizedDescription)
        }
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

    private func fetchDataWithProgress(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                Task { @MainActor [weak self] in
                    self?.progressObservation = nil
                }

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

            progressObservation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
                Task { @MainActor [weak self] in
                    let fraction = progress.fractionCompleted
                    self?.downloadProgress = fraction.isFinite ? max(0, min(1, fraction)) : 0
                    self?.statusText = AppText.downloadingUpdateProgress(
                        Int((self?.downloadProgress ?? 0) * 100)
                    )
                }
            }

            task.resume()
        }
    }

    private static func temporaryDMGDestination(tagName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("turnintoserver-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("turnintoserver-\(tagName).dmg")
    }

    private static func launchInstaller(dmgURL: URL, targetAppURL: URL) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("turnintoserver-install-\(UUID().uuidString).sh")
        let script = """
        #!/bin/bash
        set -euo pipefail

        APP_PID="$1"
        DMG="$2"
        TARGET_APP="$3"
        APP_NAME="$(/usr/bin/basename "$TARGET_APP")"
        MOUNT_DIR="$(/usr/bin/mktemp -d /tmp/turnintoserver-update.XXXXXX)"
        TMP_TARGET="$TARGET_APP.updating"
        BACKUP="$TARGET_APP.previous"

        cleanup() {
          /usr/bin/hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
          /bin/rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
        }
        trap cleanup EXIT

        while /bin/kill -0 "$APP_PID" >/dev/null 2>&1; do
          /bin/sleep 0.2
        done

        /usr/bin/hdiutil attach "$DMG" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
        SOURCE_APP="$MOUNT_DIR/$APP_NAME"
        if [[ ! -d "$SOURCE_APP" ]]; then
          SOURCE_APP="$(/usr/bin/find "$MOUNT_DIR" -maxdepth 1 -name "*.app" -type d | /usr/bin/head -n 1)"
        fi
        if [[ ! -d "$SOURCE_APP" ]]; then
          exit 1
        fi

        /bin/rm -rf "$TMP_TARGET" "$BACKUP"
        /usr/bin/ditto --norsrc --noextattr "$SOURCE_APP" "$TMP_TARGET"
        /usr/bin/xattr -cr "$TMP_TARGET" >/dev/null 2>&1 || true

        if [[ -d "$TARGET_APP" ]]; then
          /bin/mv "$TARGET_APP" "$BACKUP"
        fi

        if /bin/mv "$TMP_TARGET" "$TARGET_APP"; then
          /usr/bin/open -n "$TARGET_APP"
          /bin/rm -rf "$BACKUP"
          /bin/rm -f "$DMG"
          /bin/rmdir "$(/usr/bin/dirname "$DMG")" >/dev/null 2>&1 || true
          /bin/rm -f "$0"
          exit 0
        fi

        /bin/rm -rf "$TARGET_APP"
        if [[ -d "$BACKUP" ]]; then
          /bin/mv "$BACKUP" "$TARGET_APP"
          /usr/bin/open -n "$TARGET_APP" >/dev/null 2>&1 || true
        fi
        exit 1
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            scriptURL.path,
            "\(ProcessInfo.processInfo.processIdentifier)",
            dmgURL.path,
            targetAppURL.path
        ]
        try process.run()
    }

    private static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0

            if leftValue != rightValue {
                return leftValue > rightValue
            }
        }

        return false
    }

    private static func versionComponents(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split { !$0.isNumber }
            .compactMap { Int($0) }
    }
}
