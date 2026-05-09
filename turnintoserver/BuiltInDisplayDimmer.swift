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
            return .failure("无法载入内建显示器控制")
        }

        let displays = Self.onlineBuiltInDisplays()
        guard !displays.isEmpty else {
            return .success("未检测到在线内建屏")
        }

        var changedCount = 0
        var lastFailure: String?

        for display in displays {
            var brightness: Float = 0
            let getResult = services.getBrightness(display, &brightness)
            guard getResult == 0 else {
                lastFailure = "读取内建屏亮度失败：\(getResult)"
                continue
            }

            if savedBrightnessByDisplay[display] == nil {
                savedBrightnessByDisplay[display] = max(0, min(1, brightness))
            }

            let setResult = services.setBrightness(display, 0)
            if setResult == 0 {
                changedCount += 1
            } else {
                lastFailure = "调暗内建屏失败：\(setResult)"
            }
        }

        if changedCount > 0 {
            return .success("已调暗内建屏")
        }

        return .failure(lastFailure ?? "未能调暗内建屏")
    }

    func restoreBuiltInDisplays() -> PowerCommandResult {
        guard !savedBrightnessByDisplay.isEmpty else {
            return .success("无需恢复内建屏亮度")
        }

        guard let services else {
            return .failure("无法载入内建显示器控制")
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
                lastFailure = "恢复内建屏亮度失败：\(setResult)"
            }
        }

        savedBrightnessByDisplay = remainingBrightnessByDisplay

        if restoredCount > 0 {
            return .success("已恢复内建屏亮度")
        }

        return .failure(lastFailure ?? "未能恢复内建屏亮度")
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
