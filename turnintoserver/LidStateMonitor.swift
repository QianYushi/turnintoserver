import Foundation

final class LidStateMonitor {
    private let intervalNanoseconds: UInt64
    private var pollingTask: Task<Void, Never>?

    init(intervalSeconds: TimeInterval = 2) {
        intervalNanoseconds = UInt64(intervalSeconds * 1_000_000_000)
    }

    deinit {
        stop()
    }

    func start(onUpdate: @escaping @MainActor (LidState) -> Void) {
        stop()

        pollingTask = Task {
            while !Task.isCancelled {
                let state = await detectLidState()
                await MainActor.run {
                    onUpdate(state)
                }

                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func detectLidState() async -> LidState {
        do {
            let result = try await ShellRunner.run("/usr/sbin/ioreg", arguments: ["-r", "-k", "AppleClamshellState"])
            guard result.exitCode == 0 else {
                return .unknown
            }

            return LidState(ioregOutput: result.stdout)
        } catch {
            return .unknown
        }
    }
}
