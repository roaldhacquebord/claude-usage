import Foundation
import Testing
@testable import UsageCore

@Suite struct UsageFetcherTests {
    func fetcher(_ script: URL, timeout: TimeInterval = 5) -> UsageFetcher {
        UsageFetcher(locate: { .success(script) }, timeout: timeout)
    }

    @Test func returnsResultText() async throws {
        let script = try makeScript(#"printf '{"is_error":false,"result":"hello"}'"#)
        #expect(await fetcher(script).fetch() == .success("hello"))
    }

    @Test func passesUsageArguments() async throws {
        let script = try makeScript(#"printf '{"is_error":false,"result":"%s"}' "$*""#)
        #expect(await fetcher(script).fetch()
            == .success("-p /usage --no-session-persistence --output-format json"))
    }

    @Test func runsInWorkingDirectoryWithClaudeFirstOnPath() async throws {
        let script = try makeScript(#"printf '{"is_error":false,"result":"%s|%s"}' "$(basename "$(pwd)")" "${PATH%%:*}""#)
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let fetcher = UsageFetcher(locate: { .success(script) }, timeout: 5, workingDirectory: workDir)
        #expect(await fetcher.fetch()
            == .success("\(workDir.lastPathComponent)|\(script.deletingLastPathComponent().path)"))
    }

    @Test func claudeReportedError() async throws {
        let script = try makeScript(#"printf '{"is_error":true,"result":"Login expired"}'"#)
        #expect(await fetcher(script).fetch() == .failure(.claudeError(message: "Login expired")))
    }

    @Test func nonZeroExitUsesStderr() async throws {
        let script = try makeScript("echo 'boom' >&2\nexit 3")
        #expect(await fetcher(script).fetch() == .failure(.claudeError(message: "boom")))
    }

    @Test func nonZeroExitWithoutStderr() async throws {
        let script = try makeScript("exit 3")
        #expect(await fetcher(script).fetch()
            == .failure(.claudeError(message: "claude exited with status 3")))
    }

    @Test func nonJSONOutput() async throws {
        let script = try makeScript("echo 'not json'")
        #expect(await fetcher(script).fetch() == .failure(.unreadableOutput(sample: "not json")))
    }

    @Test func timesOut() async throws {
        let script = try makeScript("sleep 5")
        #expect(await fetcher(script, timeout: 0.5).fetch() == .failure(.timedOut))
    }

    @Test func missingExecutable() async {
        let missing = URL(fileURLWithPath: "/nonexistent/claude")
        #expect(await fetcher(missing).fetch() == .failure(.notFound(searched: ["/nonexistent/claude"])))
    }

    @Test func locateFailureIsPassedThrough() async {
        let fetcher = UsageFetcher(locate: { .failure(.notFound(searched: ["x"])) })
        #expect(await fetcher.fetch() == .failure(.notFound(searched: ["x"])))
    }

    /// Opt-in: runs the real `claude`. `CLAUDE_USAGE_E2E=1 ./test.sh --filter realClaudeEndToEnd`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CLAUDE_USAGE_E2E"] == "1"))
    func realClaudeEndToEnd() async throws {
        let text = try await UsageFetcher().fetch().get()
        let limits = UsageParser.parse(text)
        #expect(!limits.isEmpty, "Parsed no limits from: \(text.prefix(300))")
    }
}
