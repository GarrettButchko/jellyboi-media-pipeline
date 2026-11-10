import Foundation

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let stdoutData: Data
    public let stderrData: Data

    public var isSuccess: Bool {
        exitCode == 0
    }
}

public enum ProcessError: Error, LocalizedError {
    case executableNotFound(String)
    case timedOut(seconds: Double)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            return "Executable '\(name)' not found."
        case .timedOut(let sec):
            return "Process timed out after \(sec) seconds."
        }
    }
}

public struct ProcessRunner: Sendable {
    /// Runs a process asynchronously with timeout and output capture
    public static func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval = 600
    ) async throws -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ProcessError.executableNotFound(executable)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let currentDirectory = currentDirectory {
                process.currentDirectoryURL = currentDirectory
            }

            var env = ProcessInfo.processInfo.environment
            if let customEnv = environment {
                for (k, v) in customEnv {
                    env[k] = v
                }
            }
            // Ensure common paths exist in PATH for subprocesses spawned by tools
            let standardPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            if let existing = env["PATH"] {
                env["PATH"] = "\(standardPaths):\(existing)"
            } else {
                env["PATH"] = standardPaths
            }
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stateLock = NSLock()
            var didResume = false
            var timeoutTimer: DispatchSourceTimer?

            func resumeOnce(result: Result<ProcessResult, Error>) {
                stateLock.lock()
                defer { stateLock.unlock() }
                if !didResume {
                    didResume = true
                    timeoutTimer?.cancel()
                    continuation.resume(with: result)
                }
            }

            if timeout > 0 {
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler {
                    if process.isRunning {
                        process.terminate()
                    }
                    resumeOnce(result: .failure(ProcessError.timedOut(seconds: timeout)))
                }
                timer.resume()
                timeoutTimer = timer
            }

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                    let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    let outStr = String(data: outData, encoding: .utf8) ?? ""
                    let errStr = String(data: errData, encoding: .utf8) ?? ""

                    let res = ProcessResult(
                        exitCode: process.terminationStatus,
                        stdout: outStr,
                        stderr: errStr,
                        stdoutData: outData,
                        stderrData: errData
                    )
                    resumeOnce(result: .success(res))
                } catch {
                    resumeOnce(result: .failure(error))
                }
            }
        }
    }
}
