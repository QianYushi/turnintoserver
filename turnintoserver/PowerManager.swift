import Foundation

@MainActor
final class PowerManager {
    private var caffeinateProcess: Process?
    private let builtInDisplayDimmer = BuiltInDisplayDimmer()

    var isServerModeActive: Bool {
        caffeinateProcess?.isRunning == true
    }

    func enableServerMode(powerSource: PowerSource) async -> PowerCommandResult {
        let sleepDisableResult = await setSleepDisabled(true)
        guard case .success = sleepDisableResult else {
            return sleepDisableResult
        }

        let caffeinateResult = startCaffeinate(powerSource: powerSource)
        guard case .success = caffeinateResult else {
            _ = await setSleepDisabled(false)
            return caffeinateResult
        }

        switch powerSource {
        case .batteryPower:
            return .success("已在电池供电下启动")
        case .acPower:
            return .success("已在接电源下启动")
        case .unknown:
            return .success("已启动")
        }
    }

    func adoptExistingServerMode(powerSource: PowerSource) {
        startCaffeinate(powerSource: powerSource)
    }

    func restoreSleepSettings() async -> PowerCommandResult {
        stopCaffeinate()

        let result = await setSleepDisabled(false)
        guard case .success = result else {
            return result
        }

        return .success("已恢复合盖睡眠")
    }

    func dimBuiltInDisplayForClosedLid() -> PowerCommandResult {
        builtInDisplayDimmer.dimBuiltInDisplays()
    }

    func restoreBuiltInDisplayBrightness() -> PowerCommandResult {
        builtInDisplayDimmer.restoreBuiltInDisplays()
    }

    func detectSleepDisabled() async -> Bool {
        do {
            let result = try await ShellRunner.run("/usr/sbin/ioreg", arguments: ["-r", "-k", "SleepDisabled"])
            return result.stdout.contains(#""SleepDisabled" = Yes"#)
        } catch {
            return false
        }
    }

    private func setSleepDisabled(_ isDisabled: Bool) async -> PowerCommandResult {
        let value = isDisabled ? "1" : "0"
        let passwordlessResult = await runPasswordlessPmset(disablesleepValue: value)
        if case .success = passwordlessResult {
            return passwordlessResult
        }

        let authorizationResult = await installOneTimeAuthorization()
        guard case .success = authorizationResult else {
            return authorizationResult
        }

        let retryResult = await runPasswordlessPmset(disablesleepValue: value)
        guard case .success = retryResult else {
            return retryResult
        }

        return .success("OK")
    }

    private func runPasswordlessPmset(disablesleepValue value: String) async -> PowerCommandResult {
        do {
            let result = try await ShellRunner.runSudoNoPassword(
                "/usr/bin/pmset",
                arguments: ["disablesleep", value]
            )

            guard result.exitCode == 0 else {
                return .failure(Self.shortFailureMessage(from: result))
            }

            return .success("OK")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func installOneTimeAuthorization() async -> PowerCommandResult {
        let command: String
        do {
            command = try Self.oneTimeAuthorizationInstallCommand()
        } catch {
            return .failure(error.localizedDescription)
        }

        let result = await runPrivileged(command)

        switch result {
        case .success:
            return .success("OK")
        case .userCancelled:
            return .userCancelled
        case .failure(let message):
            return .failure(message)
        }
    }

    private static func oneTimeAuthorizationInstallCommand() throws -> String {
        let userName = NSUserName()
        let validCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard !userName.isEmpty,
              userName.rangeOfCharacter(from: validCharacters.inverted) == nil else {
            throw PowerManagerError.unsupportedUserName
        }

        let sudoersPath = "/private/etc/sudoers.d/turnintoserver"
        let contents = """
        # turnintoserver one-time permission for Server Mode.
        \(userName) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1

        """

        return [
            "tmp=$(/usr/bin/mktemp /tmp/turnintoserver-sudoers.XXXXXX)",
            "trap '/bin/rm -f \"$tmp\"' EXIT",
            "/usr/bin/printf %s \(ShellRunner.shellQuoted(contents)) > \"$tmp\"",
            "/usr/sbin/visudo -cf \"$tmp\" >/dev/null",
            "/usr/sbin/chown root:wheel \"$tmp\"",
            "/bin/chmod 440 \"$tmp\"",
            "/bin/mv \"$tmp\" \(ShellRunner.shellQuoted(sudoersPath))",
            "trap - EXIT"
        ].joined(separator: " && ")
    }

    @discardableResult
    private func startCaffeinate(powerSource: PowerSource) -> PowerCommandResult {
        if isServerModeActive {
            return .success("Server 模式已在运行")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        var arguments = ["-i", "-m"]
        if powerSource == .acPower {
            arguments.append("-s")
        }
        arguments += ["-w", "\(ProcessInfo.processInfo.processIdentifier)"]
        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .failure("无法启动 caffeinate：\(error.localizedDescription)")
        }

        guard process.isRunning else {
            let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(Self.shortFailureMessage(message ?? "caffeinate 已退出"))
        }

        caffeinateProcess = process
        return .success("OK")
    }

    private func stopCaffeinate() {
        guard let process = caffeinateProcess else {
            return
        }

        if process.isRunning {
            process.terminate()
        }

        caffeinateProcess = nil
    }

    private func runPrivileged(_ command: String) async -> PowerCommandResult {
        do {
            let result = try await ShellRunner.runAdministratorCommand(command)
            guard result.exitCode == 0 else {
                if ShellRunner.isUserCancelled(result) {
                    return .userCancelled
                }

                return .failure(Self.shortFailureMessage(from: result))
            }

            return .success("OK")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func shortFailureMessage(from result: ShellResult) -> String {
        shortFailureMessage(result.combinedOutput)
    }

    private static func shortFailureMessage(_ message: String) -> String {
        guard !message.isEmpty else {
            return "命令执行失败"
        }

        let firstLine = message.split(separator: "\n").first.map(String.init) ?? message
        guard firstLine.count > 36 else {
            return firstLine
        }

        return String(firstLine.prefix(33)) + "..."
    }
}
