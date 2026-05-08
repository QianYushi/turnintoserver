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
