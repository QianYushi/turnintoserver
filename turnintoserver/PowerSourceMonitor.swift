import Foundation
import IOKit.ps

final class PowerSourceMonitor {
    private var notificationSource: CFRunLoopSource?
    private var onUpdate: (@MainActor (PowerSource) -> Void)?

    deinit {
        stop()
    }

    func start(onUpdate: @escaping @MainActor (PowerSource) -> Void) {
        stop()
        self.onUpdate = onUpdate

        installPowerSourceNotification()

        Task { [weak self] in
            await self?.publishCurrentPowerSource()
        }
    }

    func stop() {
        if let notificationSource {
            CFRunLoopSourceInvalidate(notificationSource)
        }

        notificationSource = nil
        onUpdate = nil
    }

    func detectPowerSource() async -> PowerSource {
        let iokitSource = detectPowerSourceFromIOKit()
        if iokitSource != .unknown {
            return iokitSource
        }

        return await detectPowerSourceFromPmset()
    }

    func detectBatteryPercentage() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            if let type = description[kIOPSTypeKey as String] as? String,
               type != kIOPSInternalBatteryType {
                continue
            }

            guard let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Int,
                  let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Int,
                  maxCapacity > 0 else {
                continue
            }

            return min(100, max(0, Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded())))
        }

        return nil
    }

    private func installPowerSourceNotification() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let unmanagedSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else {
                return
            }

            let monitor = Unmanaged<PowerSourceMonitor>
                .fromOpaque(context)
                .takeUnretainedValue()

            Task { [weak monitor] in
                await monitor?.publishCurrentPowerSource()
            }
        }, context)

        guard let source = unmanagedSource?.takeRetainedValue() else {
            return
        }

        notificationSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func publishCurrentPowerSource() async {
        let source = await detectPowerSource()

        await MainActor.run { [weak self] in
            self?.onUpdate?(source)
        }
    }

    private func detectPowerSourceFromIOKit() -> PowerSource {
        guard let unmanagedType = IOPSGetProvidingPowerSourceType(nil) else {
            return .unknown
        }

        return PowerSource(ioKitPowerSourceType: unmanagedType.takeUnretainedValue() as String)
    }

    private func detectPowerSourceFromPmset() async -> PowerSource {
        do {
            let result = try await ShellRunner.run("/usr/bin/pmset", arguments: ["-g", "batt"])
            guard result.exitCode == 0 else {
                return .unknown
            }

            return PowerSource(pmsetBatteryOutput: result.stdout)
        } catch {
            return .unknown
        }
    }
}
