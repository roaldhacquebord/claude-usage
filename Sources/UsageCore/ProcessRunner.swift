import Darwin
import Foundation
import os

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

    /// How long to wait for a still-draining pipe reader after the process has already exited,
    /// before giving up and using whatever has been read so far.
    private static let readerJoinTimeout: TimeInterval = 2
    /// How long to give a terminated process to exit before escalating from SIGTERM to SIGKILL.
    private static let killGracePeriod: TimeInterval = 1

    /// Runs a process to completion, blocking the calling thread. Both pipes are drained
    /// concurrently on background queues while waiting for the process to exit, then joined with
    /// a bounded wait — so neither a large amount of output nor a process that leaves a
    /// background child holding a pipe's write end open (as `claude`, a Node process, could) can
    /// wedge this call: draining no longer waits for every holder of a pipe's write end to close
    /// it, only for the direct child to exit plus a short bounded join. Joining also stops the
    /// reads and closes the pipes, so nothing keeps reading on behalf of a lingering child.
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

        let stdoutReader = PipeReader(draining: stdout.fileHandleForReading)
        let stderrReader = PipeReader(draining: stderr.fileHandleForReading)

        guard exited.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            // Wait on the termination handler rather than sleeping and checking `isRunning`: once
            // the process has been reaped its PID can be reused, so SIGKILL goes out only while
            // the handler hasn't fired yet. That narrows the race but can't fully close it.
            if exited.wait(timeout: .now() + killGracePeriod) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            _ = stdoutReader.join(deadline: .now())
            _ = stderrReader.join(deadline: .now())
            return .failure(.timedOut)
        }

        // Both readers share one deadline rather than each getting their own readerJoinTimeout,
        // so a pipe that never reaches EOF (e.g. a lingering background child on both stdout and
        // stderr) adds readerJoinTimeout once total, not once per pipe.
        let joinDeadline = DispatchTime.now() + readerJoinTimeout
        return .success(ProcessOutput(
            status: process.terminationStatus,
            stdout: stdoutReader.join(deadline: joinDeadline),
            stderr: stderrReader.join(deadline: joinDeadline)))
    }
}

/// Drains a pipe on a background queue as soon as it's created, and hands back whatever has been
/// read so far when joined — so a pipe whose write end is still held open by a lingering
/// background child can't block the caller forever.
private final class PipeReader: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: Data())
    private let done = DispatchSemaphore(value: 0)
    private let channel: DispatchIO

    init(draining handle: FileHandle) {
        // A dispatch channel rather than a loop over availableData, which would block a thread in
        // read() for as long as any holder of the write end (including a lingering background
        // child) keeps it open. The channel can be stopped instead, and closes the handle itself
        // once stopped: waiting for the Pipe to be deallocated would leave it open for an
        // unpredictable while, so a lingering child could keep writing into it.
        channel = DispatchIO(
            type: .stream, fileDescriptor: handle.fileDescriptor, queue: .global(qos: .utility),
            cleanupHandler: { _ in try? handle.close() })
        channel.setLimit(lowWater: 1)
        channel.read(offset: 0, length: Int.max, queue: .global(qos: .utility)) { [storage, done] isDone, chunk, _ in
            if let chunk, !chunk.isEmpty { storage.withLock { $0.append(contentsOf: chunk) } }
            if isDone { done.signal() }
        }
    }

    /// Waits until EOF or `deadline`, then stops reading and closes the pipe.
    func join(deadline: DispatchTime) -> Data {
        _ = done.wait(timeout: deadline)
        channel.close(flags: .stop)
        return storage.withLock { $0 }
    }
}
