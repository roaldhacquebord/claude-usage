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
}
