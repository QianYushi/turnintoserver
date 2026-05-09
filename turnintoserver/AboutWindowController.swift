import AppKit
import Foundation
import SwiftUI

@MainActor
final class AboutWindowController: NSWindowController {
    init() {
        let hostingController = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = AppText.aboutApp
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 420, height: 540)
        window.contentMaxSize = NSSize(width: 420, height: 540)
        window.setContentSize(NSSize(width: 420, height: 540))
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
    @ObservedObject private var updateModel: AboutUpdateViewModel
    @ObservedObject private var iMessageModel: IMessageSettingsViewModel

    @MainActor
    init() {
        updateModel = AboutUpdateViewModel()
        iMessageModel = IMessageSettingsViewModel()
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .cornerRadius(16)

            VStack(spacing: 4) {
                Text("turnintoserver")
                    .font(.system(size: 20, weight: .semibold))
                Text(AppText.currentVersion(AboutUpdateViewModel.currentVersionDisplay))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppText.developer("qianyushi"))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(AppText.githubPrefix)
                    Button(AppText.githubURLDisplay) {
                        AboutUpdateViewModel.openGitHub()
                    }
                    .buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(AppText.shortcutHintsTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(AppText.serverModeShortcutHint)
                Text(AppText.batteryModeShortcutHint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(AppText.iMessageSettingsTitle)
                    .font(.system(size: 13, weight: .semibold))
                TextField(AppText.iMessageRecipientPlaceholder, text: $iMessageModel.recipientAddress)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                HStack(spacing: 10) {
                    Button(AppText.sendTestMessage) {
                        iMessageModel.sendTestMessage()
                    }
                    .disabled(iMessageModel.isSendingTest)

                    Text(iMessageModel.statusText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button(AppText.checkForUpdates) {
                        updateModel.checkForUpdates()
                    }
                    .disabled(updateModel.isChecking || updateModel.isDownloading)

                    if updateModel.canDownloadLatestDMG {
                        Button(AppText.downloadLatestDMG) {
                            updateModel.downloadLatestDMG()
                        }
                        .disabled(updateModel.isDownloading)
                    }

                    Spacer()
                }

                Text(updateModel.statusText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 24, leading: 26, bottom: 20, trailing: 26))
        .frame(width: 420, height: 540)
    }
}

@MainActor
private final class IMessageSettingsViewModel: ObservableObject {
    @Published var recipientAddress: String {
        didSet {
            defaults.set(recipientAddress, forKey: AppDefaultsKey.iMessageRecipientAddress)
        }
    }

    @Published var isSendingTest = false
    @Published var statusText = AppText.iMessageSettingsIdle

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recipientAddress = defaults.string(forKey: AppDefaultsKey.iMessageRecipientAddress) ?? ""
    }

    func sendTestMessage() {
        Task {
            await sendTestMessageAsync()
        }
    }

    private func sendTestMessageAsync() async {
        guard !isSendingTest else {
            return
        }

        let recipient = recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipient.isEmpty else {
            statusText = AppText.iMessageRecipientMissing
            return
        }

        isSendingTest = true
        statusText = AppText.iMessageTestSending

        defer {
            isSendingTest = false
        }

        do {
            try await IMessageNotifier.send(
                message: AppText.iMessageTestMessage(macName: IMessageNotifier.defaultMacName),
                to: recipient
            )
            statusText = AppText.iMessageTestSent
        } catch {
            statusText = AppText.iMessageTestFailed(error.localizedDescription)
        }
    }
}

@MainActor
private final class AboutUpdateViewModel: ObservableObject {
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
    @Published var statusText = AppText.updateIdle
    @Published var canDownloadLatestDMG = false

    private var latestDMGURL: URL?
    private var latestTagName: String?

    static func openGitHub() {
        NSWorkspace.shared.open(githubURL)
    }

    func checkForUpdates() {
        Task {
            await checkForUpdatesAsync()
        }
    }

    func downloadLatestDMG() {
        Task {
            await downloadLatestDMGAsync()
        }
    }

    private func checkForUpdatesAsync() async {
        guard !isChecking else {
            return
        }

        isChecking = true
        canDownloadLatestDMG = false
        latestDMGURL = nil
        latestTagName = nil
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

            latestDMGURL = dmgAsset.browserDownloadURL
            latestTagName = release.tagName
            canDownloadLatestDMG = true
            statusText = AppText.updateAvailable(release.tagName)
        } catch {
            statusText = AppText.updateCheckFailed(error.localizedDescription)
        }
    }

    private func downloadLatestDMGAsync() async {
        guard !isDownloading, let latestDMGURL else {
            return
        }

        isDownloading = true
        statusText = AppText.downloadingLatestDMG

        defer {
            isDownloading = false
        }

        do {
            let (data, response) = try await Self.fetchData(for: URLRequest(url: latestDMGURL))
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                statusText = AppText.downloadFailed(AppText.updateServerUnavailable)
                return
            }

            let destination = try Self.availableDownloadDestination(
                originalFileName: latestDMGURL.lastPathComponent,
                tagName: latestTagName
            )
            try data.write(to: destination, options: .atomic)
            statusText = AppText.downloadFinished(destination.lastPathComponent)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            statusText = AppText.downloadFailed(error.localizedDescription)
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

    private static func availableDownloadDestination(originalFileName: String, tagName: String?) throws -> URL {
        let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let fallbackName: String
        if let tagName, !tagName.isEmpty {
            fallbackName = "turnintoserver-\(tagName).dmg"
        } else {
            fallbackName = "turnintoserver.dmg"
        }

        let fileName = originalFileName.isEmpty ? fallbackName : originalFileName
        let baseURL = downloadsDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let name = baseURL.deletingPathExtension().lastPathComponent
        let pathExtension = baseURL.pathExtension
        for index in 2...999 {
            let candidateName = pathExtension.isEmpty ? "\(name) \(index)" : "\(name) \(index).\(pathExtension)"
            let candidateURL = downloadsDirectory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        throw CocoaError(.fileWriteFileExists)
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
