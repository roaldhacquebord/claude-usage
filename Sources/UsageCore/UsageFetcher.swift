import Foundation

/// Runs `claude -p /usage` and returns the text Claude Code printed.
public struct UsageFetcher: Sendable {
    /// `--safe-mode` keeps hooks, plugins, MCP servers, CLAUDE.md and custom commands from loading,
    /// so polling doesn't run them every few minutes; login and `/usage` work as normal.
    public static let defaultArguments = [
        "-p", "/usage", "--no-session-persistence", "--safe-mode", "--output-format", "json",
    ]

    private let locate: @Sendable () -> Result<URL, UsageError>
    private let arguments: [String]
    private let timeout: TimeInterval
    private let workingDirectory: URL

    /// `workingDirectory` defaults to a folder outside any project. That alone doesn't stop a
    /// `.claude/` folder there from loading; `--safe-mode` in `defaultArguments` does.
    public init(
        locate: @escaping @Sendable () -> Result<URL, UsageError> = ClaudeLocator.locate,
        arguments: [String] = UsageFetcher.defaultArguments,
        timeout: TimeInterval = 30,
        workingDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.locate = locate
        self.arguments = arguments
        self.timeout = timeout
        self.workingDirectory = workingDirectory
    }

    public func fetch() async -> Result<String, UsageError> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: fetchBlocking())
            }
        }
    }

    private func fetchBlocking() -> Result<String, UsageError> {
        let executable: URL
        switch locate() {
        case .success(let url): executable = url
        case .failure(let error): return .failure(error)
        }

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = executable.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")

        switch ProcessRunner.run(
            executable, arguments: arguments, workingDirectory: workingDirectory,
            environment: environment, timeout: timeout)
        {
        case .failure(.launchFailed): return .failure(.notFound(searched: [executable.path]))
        case .failure(.timedOut): return .failure(.timedOut)
        case .success(let output): return Self.interpret(output)
        }
    }

    static func interpret(_ output: ProcessOutput) -> Result<String, UsageError> {
        if let payload = try? JSONDecoder().decode(Payload.self, from: output.stdout) {
            return payload.isError ? .failure(.claudeError(message: payload.result)) : .success(payload.result)
        }
        if output.status != 0 {
            let stderr = String(decoding: output.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(.claudeError(message: stderr.isEmpty ? "claude exited with status \(output.status)" : stderr))
        }
        return .failure(.unreadableOutput(sample: UsageError.sample(of: String(decoding: output.stdout, as: UTF8.self))))
    }
}

private struct Payload: Decodable {
    let isError: Bool
    let result: String

    enum CodingKeys: String, CodingKey {
        case isError = "is_error"
        case result
    }
}
