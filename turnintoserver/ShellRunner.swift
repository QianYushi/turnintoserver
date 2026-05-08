import Foundation

enum ShellRunner {
    static func run(_ executablePath: String, arguments: [String]) async throws -> ShellResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                throw ShellRunnerError.launchFailed(error.localizedDescription)
            }

            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            return ShellResult(
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? "",
                exitCode: process.terminationStatus
            )
        }.value
    }

    static func runAdministratorCommand(_ shellCommand: String) async throws -> ShellResult {
        let script = #"do shell script "\#(escapeForAppleScript(shellCommand))" with administrator privileges"#
        return try await run("/usr/bin/osascript", arguments: ["-e", script])
    }

    static func runSudoNoPassword(_ executablePath: String, arguments: [String]) async throws -> ShellResult {
        try await run("/usr/bin/sudo", arguments: ["-n", executablePath] + arguments)
    }

    static func isUserCancelled(_ result: ShellResult) -> Bool {
        let output = result.combinedOutput.lowercased()
        return output.contains("user canceled")
            || output.contains("user cancelled")
            || output.contains("(-128)")
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
