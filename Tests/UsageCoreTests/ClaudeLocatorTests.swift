import Foundation
import Testing
@testable import UsageCore

@Suite struct ClaudeLocatorTests {
    @Test func fallbackPathsUseHome() {
        #expect(ClaudeLocator.fallbackPaths(home: "/Users/test") == [
            "/Users/test/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
        ])
    }

    @Test func firstExecutablePicksFirstExistingPath() throws {
        let script = try makeScript("exit 0")
        let result = ClaudeLocator.firstExecutable(in: ["/nonexistent/claude", script.path])
        #expect(result.map(\.path) == .success(script.path))
    }

    @Test func firstExecutableReportsSearchedPaths() {
        #expect(ClaudeLocator.firstExecutable(in: ["/a/claude", "/b/claude"])
            == .failure(.notFound(searched: ["your login shell's PATH", "/a/claude", "/b/claude"])))
    }

    @Test func loginShellLookupTakesLastOutputLine() throws {
        let shell = try makeScript("echo 'welcome from .zprofile'\necho /opt/tools/claude", name: "zsh")
        #expect(ClaudeLocator.lookUpViaLoginShell(shell: shell) == "/opt/tools/claude")
    }

    @Test func loginShellLookupFailureReturnsNil() throws {
        let shell = try makeScript("exit 1", name: "zsh")
        #expect(ClaudeLocator.lookUpViaLoginShell(shell: shell) == nil)
    }
}
