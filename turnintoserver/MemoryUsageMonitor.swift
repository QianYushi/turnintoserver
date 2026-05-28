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

struct MemoryUsageHistoryPoint {
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

struct SystemPressureHistoryPoint {
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
    private struct AppSeries {
        var points: [MemoryUsageHistoryPoint] = []
    }

    private let retention: TimeInterval
    private let sampleInterval: TimeInterval
    private var seriesByAppID: [String: AppSeries] = [:]
    private var systemPoints: [SystemPressureHistoryPoint] = []
    private var lastRecordedAt: Date?

    init(retention: TimeInterval = 24 * 60 * 60, sampleInterval: TimeInterval = 30) {
        self.retention = retention
        self.sampleInterval = sampleInterval
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
        systemPoints.removeAll { point in
            point.timestamp < cutoff
        }

        for entry in snapshot.entries {
            var series = seriesByAppID[entry.id] ?? AppSeries()
            series.points.append(
                MemoryUsageHistoryPoint(
                    timestamp: snapshot.timestamp,
                    residentBytes: entry.residentBytes,
                    cpuPercent: entry.cpuPercent
                )
            )
            series.points.removeAll { point in
                point.timestamp < cutoff
            }
            seriesByAppID[entry.id] = series
        }

        let expiredAppIDs = seriesByAppID.compactMap { appID, series in
            let lastTimestamp = series.points.last?.timestamp ?? .distantPast
            return (series.points.isEmpty || lastTimestamp < cutoff) ? appID : nil
        }
        for appID in expiredAppIDs {
            seriesByAppID.removeValue(forKey: appID)
        }
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

        let entries = groupedMemory.values.map { summary in
            MemoryUsageSnapshotEntry(
                id: summary.appURL.path,
                residentBytes: summary.residentBytes,
                percentOfPhysicalMemory: physicalMemory > 0
                    ? (Double(summary.residentBytes) / physicalMemory) * 100
                    : 0,
                cpuPercent: summary.cpuPercent
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
            cpuPercent: max(cpuPercent, 0)
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
        let processorCount = max(ProcessInfo.processInfo.processorCount, 1)
        let totalCPUPercent = samples.reduce(0) { $0 + $1.cpuPercent }
        return totalCPUPercent / Double(processorCount)
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
        let bundle = Bundle(url: appURL)
        let info = bundle?.localizedInfoDictionary ?? bundle?.infoDictionary
        let name = info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? info?["CFBundleExecutable"] as? String
            ?? appURL.deletingPathExtension().lastPathComponent

        return name.isEmpty ? appURL.deletingPathExtension().lastPathComponent : name
    }
}
