import Foundation
import os

/// Finds the `claude` executable. Apps started from Finder don't get the shell's PATH,
/// so ask the login shell first, then try the usual install locations.
public enum ClaudeLocator {
    public static func locate() -> Result<URL, UsageError> {
        if let path = lookUpViaLoginShell(), FileManager.default.isExecutableFile(atPath: path) {
            return .success(URL(fileURLWithPath: path))
        }
        return firstExecutable(in: fallbackPaths())
    }

    static func fallbackPaths(home: String = NSHomeDirectory()) -> [String] {
        ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
    }

    static func firstExecutable(in paths: [String]) -> Result<URL, UsageError> {
        if let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return .success(URL(fileURLWithPath: path))
        }
        return .failure(.notFound(searched: ["your login shell's PATH"] + paths))
    }

    /// Runs `command -v claude` in a login shell. Takes the last output line, since shell
    /// startup files sometimes print a greeting first.
    static func lookUpViaLoginShell(shell: URL = URL(fileURLWithPath: "/bin/zsh")) -> String? {
        guard
            case .success(let output) = ProcessRunner.run(shell, arguments: ["-lc", "command -v claude"], timeout: 10),
            output.status == 0
        else { return nil }
        return String(decoding: output.stdout, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .last
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

/// Remembers where `claude` was found, so polling doesn't start a login shell every time. Looks
/// again once that path stops being executable, e.g. after an uninstall. Failures aren't
/// remembered, so installing `claude` later is picked up on the next poll.
public final class CachingClaudeLocator: Sendable {
    private let lookUp: @Sendable () -> Result<URL, UsageError>
    private let cached = OSAllocatedUnfairLock<URL?>(initialState: nil)

    public init(lookUp: @escaping @Sendable () -> Result<URL, UsageError> = ClaudeLocator.locate) {
        self.lookUp = lookUp
    }

    public func locate() -> Result<URL, UsageError> {
        if let url = cached.withLock({ $0 }), FileManager.default.isExecutableFile(atPath: url.path) {
            return .success(url)
        }
        let result = lookUp()
        cached.withLock { $0 = try? result.get() }
        return result
    }
}
