import Foundation
import Testing
@testable import UsageCore

@Suite struct ProcessRunnerTests {
    /// A `claude` process is a Node process; if it ever leaves a background child that inherited
    /// stdout/stderr, draining the pipes must not wait for that lingering child to close them too.
    @Test func doesNotBlockOnLingeringBackgroundChild() throws {
        let script = try makeScript("sleep 30 &\necho ready\nexit 0")

        let start = Date()
        let result = ProcessRunner.run(script, arguments: [], timeout: 5)
        let elapsed = Date().timeIntervalSince(start)

        switch result {
        case .success(let output):
            #expect(String(decoding: output.stdout, as: UTF8.self).contains("ready"))
        case .failure(let failure):
            Issue.record("expected .success, got \(failure)")
        }
        #expect(elapsed < 5, "took \(elapsed)s — pipe read likely blocked on the lingering background child")
    }

    @Test func killsProcessThatIgnoresTerminate() throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let script = try makeScript("trap '' TERM\necho $$ > '\(pidFile.path)'\nexec sleep 30")

        guard case .failure(.timedOut) = ProcessRunner.run(script, arguments: [], timeout: 0.5) else {
            Issue.record("expected .failure(.timedOut)")
            return
        }

        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)))
        // Foundation reaps the killed process asynchronously, so give it a moment to disappear.
        let deadline = Date().addingTimeInterval(2)
        while kill(pid, 0) == 0 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        #expect(kill(pid, 0) == -1, "process \(pid) survived the SIGKILL escalation")
    }
}
