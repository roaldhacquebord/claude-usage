import Foundation

struct ProcessOutput: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
}

enum ProcessRunner {
    enum Failure: Error, Equatable {
        case launchFailed
        case timedOut
    }

    /// Runs a process to completion, blocking the calling thread. Output is read after the process
    /// exits, which is fine for the few KB used here: pipe buffers hold 64 KB before a writer blocks.
    static func run(
        _ executable: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval
    ) -> Result<ProcessOutput, Failure> {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        if let environment { process.environment = environment }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return .failure(.launchFailed)
        }
        guard exited.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return .failure(.timedOut)
        }
        return .success(ProcessOutput(
            status: process.terminationStatus,
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile()))
    }
}
