import Foundation

public struct ProcessResult: Sendable {
    public var stdout: String
    public var stderr: String
    public var status: Int32
}

public enum ToolLocator {
    public static func find(_ name: String) async -> String? {
        for directory in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
            let path = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        do {
            let result = try await ProcessRunner.run("/usr/bin/which", [name], environment: [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            ])
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        } catch {
            return nil
        }
    }
}

public enum ProcessRunner {
    public static func run(
        _ executablePath: String,
        _ arguments: [String],
        currentDirectory: URL? = nil,
        standardInput: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            if let currentDirectory {
                process.currentDirectoryURL = currentDirectory
            }

            // GUI apps launched from Finder/Dock inherit a minimal PATH that omits
            // Homebrew (/opt/homebrew/bin) and /usr/local/bin. Tools like `whisper`
            // shell out to bare `ffmpeg` and silently skip (exit 0, no output) when
            // it is not on PATH. Always guarantee the common tool directories are on
            // PATH so child processes can locate their own dependencies.
            var resolvedEnvironment = ProcessInfo.processInfo.environment
            let toolDirectories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            let existingPath = resolvedEnvironment["PATH"] ?? ""
            let existingEntries = existingPath.split(separator: ":").map(String.init)
            let mergedEntries = toolDirectories + existingEntries.filter { !toolDirectories.contains($0) }
            resolvedEnvironment["PATH"] = mergedEntries.joined(separator: ":")
            if let environment {
                resolvedEnvironment.merge(environment) { _, new in new }
            }
            process.environment = resolvedEnvironment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            if standardInput != nil {
                process.standardInput = stdinPipe
            }

            try process.run()
            if let standardInput, let data = standardInput.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
                try? stdinPipe.fileHandleForWriting.close()
            }
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let result = ProcessResult(stdout: stdout, stderr: stderr, status: process.terminationStatus)

            if process.terminationStatus != 0 {
                let command = ([executablePath] + arguments).joined(separator: " ")
                throw Clip4XError.commandFailed(command, process.terminationStatus, stderr)
            }

            return result
        }.value
    }
}
