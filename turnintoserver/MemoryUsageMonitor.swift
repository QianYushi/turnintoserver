import AppKit
import Darwin
import Foundation

fileprivate enum MemoryDisplayFormat {
    static func gigabytes(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / 1024 / 1024 / 1024
        return String(format: "%.2fGB", gigabytes)
    }

    static func cpuLabel(_ cpuPercent: Double) -> String {
        String(format: "%.1f%%", cpuPercent)
    }
}

struct MemoryUsageApp: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let residentBytes: UInt64
    let percentOfPhysicalMemory: Double
    let cpuPercent: Double

    var memoryDisplay: String {
        MemoryDisplayFormat.gigabytes(residentBytes)
    }

    var percentDisplay: String {
        MemoryDisplayFormat.cpuLabel(cpuPercent)
    }
}

struct MemoryUsageSnapshotEntry: Sendable {
    let id: String
    let name: String
    let residentBytes: UInt64
    let percentOfPhysicalMemory: Double
    let cpuPercent: Double
}

struct MemoryUsageSnapshot: Sendable {
    let timestamp: Date
    let entries: [MemoryUsageSnapshotEntry]
    let systemPressure: SystemPressureSnapshot
}

struct SystemPressureSnapshot: Sendable {
    let memoryUsedBytes: UInt64
    let memoryPercent: Double
    let cpuPercent: Double

    var memoryPercentDisplay: String {
        String(format: "%.1f%%", memoryPercent)
    }

    var cpuPercentDisplay: String {
        String(format: "%.1f%%", cpuPercent)
    }

    var cpuLabelDisplay: String {
        MemoryDisplayFormat.cpuLabel(cpuPercent)
    }

    var memoryDisplay: String {
        MemoryDisplayFormat.gigabytes(memoryUsedBytes)
    }
}

struct MemoryUsageHistoryPoint: Codable {
    let timestamp: Date
    let residentBytes: UInt64
    let cpuPercent: Double
}

struct MemoryUsageHistory {
    let appID: String
    let appName: String
    let currentBytes: UInt64
    let currentCPUPercent: Double
    let peakBytes: UInt64
    let peakCPUPercent: Double
    let physicalMemoryBytes: UInt64
    let points: [MemoryUsageHistoryPoint]
}

struct SystemPressureHistoryPoint: Codable {
    let timestamp: Date
    let memoryUsedBytes: UInt64
    let memoryPercent: Double
    let cpuPercent: Double
}

struct SystemPressureHistory {
    static let id = "__system_pressure__"

    let current: SystemPressureSnapshot
    let peakMemoryUsedBytes: UInt64
    let peakMemoryPercent: Double
    let peakCPUPercent: Double
    let physicalMemoryBytes: UInt64
    let points: [SystemPressureHistoryPoint]
}

final class MemoryUsageHistoryStore {
    static let historyStorage = "persistent_file"
    static let historyNote = "History is persisted under Application Support across app restarts and updates, retained up to 24 hours. Samples are collected only while turnintoserver is running."

    private struct AppSeries: Codable {
        var appName: String
        var points: [MemoryUsageHistoryPoint] = []
    }

    private struct PersistedHistory: Codable {
        let version: Int
        let savedAt: Date
        let seriesByAppID: [String: AppSeries]
        let systemPoints: [SystemPressureHistoryPoint]
    }

    private let retention: TimeInterval
    private let sampleInterval: TimeInterval
    private let persistenceURL: URL
    private var seriesByAppID: [String: AppSeries] = [:]
    private var systemPoints: [SystemPressureHistoryPoint] = []
    private var lastRecordedAt: Date?

    init(
        retention: TimeInterval = 24 * 60 * 60,
        sampleInterval: TimeInterval = 30,
        persistenceURL: URL = MemoryUsageHistoryStore.defaultPersistenceURL()
    ) {
        self.retention = retention
        self.sampleInterval = sampleInterval
        self.persistenceURL = persistenceURL
        loadPersistedHistory()
    }

    func recordIfNeeded(snapshot: MemoryUsageSnapshot) {
        if let lastRecordedAt,
           snapshot.timestamp.timeIntervalSince(lastRecordedAt) < sampleInterval {
            return
        }

        lastRecordedAt = snapshot.timestamp
        let cutoff = snapshot.timestamp.addingTimeInterval(-retention)
        systemPoints.append(
            SystemPressureHistoryPoint(
                timestamp: snapshot.timestamp,
                memoryUsedBytes: snapshot.systemPressure.memoryUsedBytes,
                memoryPercent: snapshot.systemPressure.memoryPercent,
                cpuPercent: snapshot.systemPressure.cpuPercent
            )
        )

        for entry in snapshot.entries {
            var series = seriesByAppID[entry.id] ?? AppSeries(appName: entry.name)
            series.appName = entry.name
            series.points.append(
                MemoryUsageHistoryPoint(
                    timestamp: snapshot.timestamp,
                    residentBytes: entry.residentBytes,
                    cpuPercent: entry.cpuPercent
                )
            )
            seriesByAppID[entry.id] = series
        }

        prune(cutoff: cutoff)
        persistHistory()
    }

    func history(matching query: String, physicalMemoryBytes: UInt64) -> MemoryUsageHistory? {
        let normalizedQuery = Self.normalized(query)
        guard !normalizedQuery.isEmpty else {
            return nil
        }

        let scoredMatches = seriesByAppID.compactMap { appID, series -> (score: Int, appID: String, series: AppSeries)? in
            guard !series.points.isEmpty else {
                return nil
            }

            let normalizedAppID = Self.normalized(appID)
            let normalizedAppName = Self.normalized(series.appName)
            let normalizedBundleName = Self.normalizedBundleName(appID)
            let score: Int

            if normalizedAppID == normalizedQuery || normalizedAppName == normalizedQuery || normalizedBundleName == normalizedQuery {
                score = 100
            } else if normalizedAppName.contains(normalizedQuery) || normalizedBundleName.contains(normalizedQuery) {
                score = 80
            } else if normalizedAppID.contains(normalizedQuery) {
                score = 60
            } else {
                return nil
            }

            return (score, appID, series)
        }

        guard let match = scoredMatches.sorted(by: { left, right in
            if left.score != right.score {
                return left.score > right.score
            }
            return left.series.points.count > right.series.points.count
        }).first,
              let current = match.series.points.last else {
            return nil
        }

        let peakBytes = match.series.points.map(\.residentBytes).max() ?? current.residentBytes
        let peakCPUPercent = match.series.points.map(\.cpuPercent).max() ?? current.cpuPercent
        return MemoryUsageHistory(
            appID: match.appID,
            appName: match.series.appName,
            currentBytes: current.residentBytes,
            currentCPUPercent: current.cpuPercent,
            peakBytes: peakBytes,
            peakCPUPercent: peakCPUPercent,
            physicalMemoryBytes: physicalMemoryBytes,
            points: match.series.points
        )
    }

    func history(for app: MemoryUsageApp, physicalMemoryBytes: UInt64) -> MemoryUsageHistory? {
        var points = seriesByAppID[app.id]?.points ?? []
        if points.isEmpty {
            return MemoryUsageHistory(
                appID: app.id,
                appName: app.name,
                currentBytes: app.residentBytes,
                currentCPUPercent: app.cpuPercent,
                peakBytes: app.residentBytes,
                peakCPUPercent: app.cpuPercent,
                physicalMemoryBytes: physicalMemoryBytes,
                points: [
                    MemoryUsageHistoryPoint(
                        timestamp: Date(),
                        residentBytes: app.residentBytes,
                        cpuPercent: app.cpuPercent
                    )
                ]
            )
        }

        if points.last?.residentBytes != app.residentBytes
            || points.last?.cpuPercent != app.cpuPercent {
            points.append(
                MemoryUsageHistoryPoint(
                    timestamp: Date(),
                    residentBytes: app.residentBytes,
                    cpuPercent: app.cpuPercent
                )
            )
        }

        let peakBytes = points.map(\.residentBytes).max() ?? app.residentBytes
        let peakCPUPercent = points.map(\.cpuPercent).max() ?? app.cpuPercent
        return MemoryUsageHistory(
            appID: app.id,
            appName: app.name,
            currentBytes: app.residentBytes,
            currentCPUPercent: app.cpuPercent,
            peakBytes: max(peakBytes, app.residentBytes),
            peakCPUPercent: max(peakCPUPercent, app.cpuPercent),
            physicalMemoryBytes: physicalMemoryBytes,
            points: points
        )
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func normalizedBundleName(_ appID: String) -> String {
        let lastComponent = URL(fileURLWithPath: appID).lastPathComponent
        let name = lastComponent.hasSuffix(".app") ? String(lastComponent.dropLast(4)) : lastComponent
        return normalized(name)
    }

    func systemHistory(
        current: SystemPressureSnapshot?,
        physicalMemoryBytes: UInt64
    ) -> SystemPressureHistory? {
        var points = systemPoints
        if let current {
            if points.isEmpty
                || points.last?.memoryUsedBytes != current.memoryUsedBytes
                || points.last?.cpuPercent != current.cpuPercent {
                points.append(
                    SystemPressureHistoryPoint(
                        timestamp: Date(),
                        memoryUsedBytes: current.memoryUsedBytes,
                        memoryPercent: current.memoryPercent,
                        cpuPercent: current.cpuPercent
                    )
                )
            }
        }

        guard let effectiveCurrent = current ?? points.last.map({
            SystemPressureSnapshot(
                memoryUsedBytes: $0.memoryUsedBytes,
                memoryPercent: $0.memoryPercent,
                cpuPercent: $0.cpuPercent
            )
        }) else {
            return nil
        }

        return SystemPressureHistory(
            current: effectiveCurrent,
            peakMemoryUsedBytes: points.map(\.memoryUsedBytes).max() ?? effectiveCurrent.memoryUsedBytes,
            peakMemoryPercent: points.map(\.memoryPercent).max() ?? effectiveCurrent.memoryPercent,
            peakCPUPercent: points.map(\.cpuPercent).max() ?? effectiveCurrent.cpuPercent,
            physicalMemoryBytes: physicalMemoryBytes,
            points: points
        )
    }

    private static func defaultPersistenceURL() -> URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("turnintoserver", isDirectory: true)

        return directory.appendingPathComponent("memory-history-v1.plist")
    }

    private func loadPersistedHistory() {
        guard let data = try? Data(contentsOf: persistenceURL),
              !data.isEmpty else {
            return
        }

        do {
            let persisted = try PropertyListDecoder().decode(PersistedHistory.self, from: data)
            systemPoints = persisted.systemPoints.sorted { $0.timestamp < $1.timestamp }
            seriesByAppID = persisted.seriesByAppID.mapValues { series in
                AppSeries(
                    appName: series.appName,
                    points: series.points.sorted { $0.timestamp < $1.timestamp }
                )
            }

            let latestAppTimestamp = seriesByAppID.values
                .compactMap { $0.points.last?.timestamp }
                .max()
            lastRecordedAt = [systemPoints.last?.timestamp, latestAppTimestamp]
                .compactMap { $0 }
                .max()

            prune(cutoff: Date().addingTimeInterval(-retention))
        } catch {
            NSLog("turnintoserver failed to load memory history: \(error.localizedDescription)")
        }
    }

    private func persistHistory() {
        do {
            try FileManager.default.createDirectory(
                at: persistenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )

            let persisted = PersistedHistory(
                version: 1,
                savedAt: Date(),
                seriesByAppID: seriesByAppID,
                systemPoints: systemPoints
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(persisted)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            NSLog("turnintoserver failed to persist memory history: \(error.localizedDescription)")
        }
    }

    private func prune(cutoff: Date) {
        systemPoints.removeAll { point in
            point.timestamp < cutoff
        }

        for appID in Array(seriesByAppID.keys) {
            guard var series = seriesByAppID[appID] else {
                continue
            }

            series.points.removeAll { point in
                point.timestamp < cutoff
            }
            if !series.points.isEmpty {
                seriesByAppID[appID] = series
            } else {
                seriesByAppID.removeValue(forKey: appID)
            }
        }
    }
}

final class MemoryUsageMonitor {
    private struct SystemCPUTicks {
        let active: UInt64
        let idle: UInt64

        var total: UInt64 {
            active + idle
        }
    }

    private struct ProcessMemorySample: Sendable {
        let residentBytes: UInt64
        let cpuPercent: Double
        let executablePath: String
    }

    private var previousSystemCPUTicks: SystemCPUTicks?

    func currentSnapshot() async -> MemoryUsageSnapshot {
        let samples = await Self.loadProcessMemorySamples()
        let fallbackCPUPercent = Self.normalizedProcessCPUPercent(from: samples)
        let systemCPUPercent = Self.currentSystemCPUPercent(
            previousTicks: &previousSystemCPUTicks,
            fallbackPercent: fallbackCPUPercent
        )
        return Self.makeSnapshot(from: samples, systemCPUPercent: systemCPUPercent)
    }

    @MainActor
    func topApplications(from snapshot: MemoryUsageSnapshot, limit: Int) -> [MemoryUsageApp] {
        Self.makeApplicationSummaries(from: snapshot, limit: limit)
    }

    private static func loadProcessMemorySamples() async -> [ProcessMemorySample] {
        await Task.detached(priority: .utility) {
            let process = Process()
            let outputPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-axo", "pid=,rss=,pcpu=,comm="]
            process.standardOutput = outputPipe
            process.standardError = Pipe()

            do {
                process.environment = utf8ProcessEnvironment()
                try process.run()
            } catch {
                return []
            }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8) else {
                return []
            }

            return output
                .split(separator: "\n")
                .compactMap(parseProcessMemorySample)
        }
        .value
    }

    private static func utf8ProcessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["LANG"] = "en_US.UTF-8"
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["LC_CTYPE"] = "en_US.UTF-8"
        return environment
    }

    private static func parseProcessMemorySample(_ line: Substring) -> ProcessMemorySample? {
        let parts = line.split(maxSplits: 3) { character in
            character == " " || character == "\t"
        }

        guard parts.count == 4,
              UInt32(parts[0]) != nil,
              let residentKilobytes = UInt64(parts[1]),
              let cpuPercent = Double(parts[2]) else {
            return nil
        }

        let executablePath = String(parts[3])
        guard !executablePath.isEmpty else {
            return nil
        }

        return ProcessMemorySample(
            residentBytes: residentKilobytes * 1024,
            cpuPercent: max(cpuPercent, 0),
            executablePath: executablePath
        )
    }

    private static func makeSnapshot(
        from samples: [ProcessMemorySample],
        systemCPUPercent: Double
    ) -> MemoryUsageSnapshot {
        let physicalMemoryBytes = ProcessInfo.processInfo.physicalMemory
        let physicalMemory = Double(physicalMemoryBytes)
        var groupedMemory: [String: (appURL: URL, residentBytes: UInt64, cpuPercent: Double)] = [:]

        for sample in samples {
            guard let appURL = outerApplicationURL(fromExecutablePath: sample.executablePath) else {
                continue
            }

            let key = appURL.path
            if let existing = groupedMemory[key] {
                groupedMemory[key] = (
                    appURL: existing.appURL,
                    residentBytes: existing.residentBytes + sample.residentBytes,
                    cpuPercent: existing.cpuPercent + sample.cpuPercent
                )
            } else {
                groupedMemory[key] = (
                    appURL: appURL,
                    residentBytes: sample.residentBytes,
                    cpuPercent: sample.cpuPercent
                )
            }
        }

        let processorCount = Self.logicalProcessorCount
        let entries = groupedMemory.values.map { summary in
            MemoryUsageSnapshotEntry(
                id: summary.appURL.path,
                name: summary.appURL.deletingPathExtension().lastPathComponent,
                residentBytes: summary.residentBytes,
                percentOfPhysicalMemory: physicalMemory > 0
                    ? (Double(summary.residentBytes) / physicalMemory) * 100
                    : 0,
                cpuPercent: Self.overallCPUPercent(
                    fromProcessCPUPercent: summary.cpuPercent,
                    processorCount: processorCount
                )
            )
        }

        return MemoryUsageSnapshot(
            timestamp: Date(),
            entries: entries.sorted { lhs, rhs in
                lhs.residentBytes > rhs.residentBytes
            },
            systemPressure: makeSystemPressure(
                cpuPercent: systemCPUPercent,
                physicalMemoryBytes: physicalMemoryBytes
            )
        )
    }

    private static func makeSystemPressure(
        cpuPercent: Double,
        physicalMemoryBytes: UInt64
    ) -> SystemPressureSnapshot {
        let memoryUsedBytes = currentActivityMonitorUsedMemoryBytes() ?? 0
        let memoryPercent = physicalMemoryBytes > 0
            ? (Double(memoryUsedBytes) / Double(physicalMemoryBytes)) * 100
            : 0

        return SystemPressureSnapshot(
            memoryUsedBytes: memoryUsedBytes,
            memoryPercent: min(max(memoryPercent, 0), 100),
            cpuPercent: Self.clampedPercent(cpuPercent)
        )
    }

    private static func currentActivityMonitorUsedMemoryBytes() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { statsPointer in
            statsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        let accountedPages = UInt64(stats.active_count)
            + UInt64(stats.inactive_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)
        let reclaimablePages = UInt64(stats.external_page_count)
            + UInt64(stats.purgeable_count)
        let usedPages = accountedPages > reclaimablePages
            ? accountedPages - reclaimablePages
            : accountedPages
        return usedPages * UInt64(vm_kernel_page_size)
    }

    private static func normalizedProcessCPUPercent(from samples: [ProcessMemorySample]) -> Double {
        let totalCPUPercent = samples.reduce(0) { $0 + $1.cpuPercent }
        return overallCPUPercent(fromProcessCPUPercent: totalCPUPercent)
    }

    private static var logicalProcessorCount: Int {
        max(ProcessInfo.processInfo.processorCount, 1)
    }

    private static func overallCPUPercent(fromProcessCPUPercent cpuPercent: Double) -> Double {
        overallCPUPercent(
            fromProcessCPUPercent: cpuPercent,
            processorCount: logicalProcessorCount
        )
    }

    private static func overallCPUPercent(
        fromProcessCPUPercent cpuPercent: Double,
        processorCount: Int
    ) -> Double {
        clampedPercent(cpuPercent / Double(max(processorCount, 1)))
    }

    private static func clampedPercent(_ percent: Double) -> Double {
        min(max(percent, 0), 100)
    }

    private static func currentSystemCPUPercent(
        previousTicks: inout SystemCPUTicks?,
        fallbackPercent: Double
    ) -> Double {
        guard let currentTicks = currentSystemCPUTicks() else {
            return fallbackPercent
        }

        defer {
            previousTicks = currentTicks
        }

        guard let previousTicks else {
            return fallbackPercent
        }

        let activeDelta = currentTicks.active >= previousTicks.active
            ? currentTicks.active - previousTicks.active
            : 0
        let totalDelta = currentTicks.total >= previousTicks.total
            ? currentTicks.total - previousTicks.total
            : 0

        guard totalDelta > 0 else {
            return fallbackPercent
        }

        return (Double(activeDelta) / Double(totalDelta)) * 100
    }

    private static func currentSystemCPUTicks() -> SystemCPUTicks? {
        var cpuInfo: processor_info_array_t?
        var processorCount: mach_msg_type_number_t = 0
        var processorInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &processorInfoCount
        )

        guard result == KERN_SUCCESS,
              let cpuInfo else {
            return nil
        }
        defer {
            let byteCount = Int(processorInfoCount) * MemoryLayout<integer_t>.stride
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: cpuInfo)),
                vm_size_t(byteCount)
            )
        }

        let stride = Int(CPU_STATE_MAX)
        var user: UInt64 = 0
        var system: UInt64 = 0
        var nice: UInt64 = 0
        var idle: UInt64 = 0

        for processorIndex in 0..<Int(processorCount) {
            let offset = processorIndex * stride
            user += UInt64(cpuInfo[offset + Int(CPU_STATE_USER)])
            system += UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            nice += UInt64(cpuInfo[offset + Int(CPU_STATE_NICE)])
            idle += UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)])
        }

        return SystemCPUTicks(active: user + system + nice, idle: idle)
    }

    @MainActor
    private static func makeApplicationSummaries(
        from snapshot: MemoryUsageSnapshot,
        limit: Int
    ) -> [MemoryUsageApp] {
        snapshot.entries
            .prefix(max(0, limit))
            .map { entry in
                let icon = NSWorkspace.shared.icon(forFile: entry.id)
                icon.size = NSSize(width: 18, height: 18)

                return MemoryUsageApp(
                    id: entry.id,
                    name: displayName(for: URL(fileURLWithPath: entry.id, isDirectory: true)),
                    icon: icon,
                    residentBytes: entry.residentBytes,
                    percentOfPhysicalMemory: entry.percentOfPhysicalMemory,
                    cpuPercent: entry.cpuPercent
                )
            }
    }

    private static func outerApplicationURL(fromExecutablePath executablePath: String) -> URL? {
        let components = executablePath.split(separator: "/", omittingEmptySubsequences: true)
        var appPathComponents: [String] = []

        for component in components {
            appPathComponents.append(String(component))
            if component.lowercased().hasSuffix(".app") {
                return URL(
                    fileURLWithPath: "/" + appPathComponents.joined(separator: "/"),
                    isDirectory: true
                )
                .standardizedFileURL
            }
        }

        return nil
    }

    @MainActor
    private static func displayName(for appURL: URL) -> String {
        let bundles = metadataBundles(for: appURL)
        let englishName = displayName(from: bundles.compactMap(englishInfoPlistStrings), requiresNonCJK: true)
        let baseEnglishName = displayName(from: bundles.map(\.infoDictionary), requiresNonCJK: true)
        let localizedName = displayName(from: bundles.map(\.localizedInfoDictionary), requiresNonCJK: false)
        let baseName = displayName(from: bundles.map(\.infoDictionary), requiresNonCJK: false)
        let pathName = normalizedDisplayName(appURL.lastPathComponent)

        return englishName
            ?? baseEnglishName
            ?? localizedName
            ?? baseName
            ?? pathName
            ?? appURL.deletingPathExtension().lastPathComponent
    }

    private static func metadataBundles(for appURL: URL) -> [Bundle] {
        let candidates = [
            appURL,
            appURL.appendingPathComponent("WrappedBundle", isDirectory: true)
        ]

        return candidates.compactMap { url in
            guard let bundle = Bundle(url: url), bundle.infoDictionary != nil else {
                return nil
            }
            return bundle
        }
    }

    private static func englishInfoPlistStrings(from bundle: Bundle) -> [String: Any]? {
        guard let url = bundle.url(
            forResource: "InfoPlist",
            withExtension: "strings",
            subdirectory: nil,
            localization: "en"
        ),
              let info = NSDictionary(contentsOf: url) as? [String: Any] else {
            return nil
        }

        return info
    }

    private static func displayName(from infos: [[String: Any]?], requiresNonCJK: Bool) -> String? {
        let keys = ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"]
        for key in keys {
            for info in infos {
                guard let name = normalizedDisplayName(info?[key] as? String) else {
                    continue
                }
                if !requiresNonCJK || !containsCJK(name) {
                    return name
                }
            }
        }
        return nil
    }

    private static func normalizedDisplayName(_ rawName: String?) -> String? {
        var name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if name?.lowercased().hasSuffix(".app") == true {
            name = String(name?.dropLast(4) ?? "")
        }
        return name?.isEmpty == false ? name : nil
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }
}
