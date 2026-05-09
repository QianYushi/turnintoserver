import CoreGraphics
import Darwin
import Foundation

final class BuiltInDisplayDimmer {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private struct DisplayServices {
        let getBrightness: GetBrightness
        let setBrightness: SetBrightness
    }

    private var savedBrightnessByDisplay = [CGDirectDisplayID: Float]()
    private let services: DisplayServices?

    init() {
        services = Self.loadDisplayServices()
    }

    func dimBuiltInDisplays() -> PowerCommandResult {
        guard let services else {
            return .failure(AppText.builtInDisplayControlUnavailable)
        }

        let displays = Self.onlineBuiltInDisplays()
        guard !displays.isEmpty else {
            return .success(AppText.noOnlineBuiltInDisplay)
        }

        var changedCount = 0
        var lastFailure: String?

        for display in displays {
            var brightness: Float = 0
            let getResult = services.getBrightness(display, &brightness)
            guard getResult == 0 else {
                lastFailure = AppText.readBuiltInDisplayBrightnessFailed(getResult)
                continue
            }

            if savedBrightnessByDisplay[display] == nil {
                savedBrightnessByDisplay[display] = max(0, min(1, brightness))
            }

            let setResult = services.setBrightness(display, 0)
            if setResult == 0 {
                changedCount += 1
            } else {
                lastFailure = AppText.dimBuiltInDisplayFailed(setResult)
            }
        }

        if changedCount > 0 {
            return .success(AppText.builtInDisplayDimmed)
        }

        return .failure(lastFailure ?? AppText.couldNotDimBuiltInDisplay)
    }

    func restoreBuiltInDisplays() -> PowerCommandResult {
        guard !savedBrightnessByDisplay.isEmpty else {
            return .success(AppText.noBuiltInDisplayBrightnessRestoreNeeded)
        }

        guard let services else {
            return .failure(AppText.builtInDisplayControlUnavailable)
        }

        var restoredCount = 0
        var remainingBrightnessByDisplay = [CGDirectDisplayID: Float]()
        var lastFailure: String?

        for (display, brightness) in savedBrightnessByDisplay {
            let setResult = services.setBrightness(display, brightness)
            if setResult == 0 {
                restoredCount += 1
            } else {
                remainingBrightnessByDisplay[display] = brightness
                lastFailure = AppText.restoreBuiltInDisplayBrightnessFailed(setResult)
            }
        }

        savedBrightnessByDisplay = remainingBrightnessByDisplay

        if restoredCount > 0 {
            return .success(AppText.builtInDisplayBrightnessRestored)
        }

        return .failure(lastFailure ?? AppText.couldNotRestoreBuiltInDisplayBrightness)
    }

    static func hasOnlineExternalDisplay() -> Bool {
        onlineDisplays().contains { CGDisplayIsBuiltin($0) == 0 }
    }

    private static func onlineBuiltInDisplays() -> [CGDirectDisplayID] {
        onlineDisplays().filter { CGDisplayIsBuiltin($0) != 0 }
    }

    private static func onlineDisplays() -> [CGDirectDisplayID] {
        let maxDisplays: UInt32 = 16
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0

        guard CGGetOnlineDisplayList(maxDisplays, &displays, &displayCount) == .success else {
            return []
        }

        return Array(displays.prefix(Int(displayCount)))
    }

    private static func loadDisplayServices() -> DisplayServices? {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            return nil
        }

        guard let getSymbol = dlsym(handle, "DisplayServicesGetBrightness"),
              let setSymbol = dlsym(handle, "DisplayServicesSetBrightness") else {
            dlclose(handle)
            return nil
        }

        return DisplayServices(
            getBrightness: unsafeBitCast(getSymbol, to: GetBrightness.self),
            setBrightness: unsafeBitCast(setSymbol, to: SetBrightness.self)
        )
    }
}
