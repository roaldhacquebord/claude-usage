import Foundation
import os
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

    @Test func cacheReusesPathWhileExecutable() throws {
        let script = try makeScript("exit 0")
        let lookUps = OSAllocatedUnfairLock(initialState: 0)
        let locator = CachingClaudeLocator(lookUp: {
            lookUps.withLock { $0 += 1 }
            return .success(script)
        })
        #expect(locator.locate() == .success(script))
        #expect(locator.locate() == .success(script))
        #expect(lookUps.withLock { $0 } == 1)
    }

    @Test func cacheLooksAgainOncePathIsGone() throws {
        let script = try makeScript("exit 0")
        let lookUps = OSAllocatedUnfairLock(initialState: 0)
        let locator = CachingClaudeLocator(lookUp: {
            lookUps.withLock { $0 += 1 }
            return .success(script)
        })
        _ = locator.locate()
        try FileManager.default.removeItem(at: script)
        _ = locator.locate()
        #expect(lookUps.withLock { $0 } == 2)
    }

    @Test func cacheDoesNotRememberFailures() {
        let lookUps = OSAllocatedUnfairLock(initialState: 0)
        let locator = CachingClaudeLocator(lookUp: {
            lookUps.withLock { $0 += 1 }
            return .failure(.notFound(searched: []))
        })
        _ = locator.locate()
        _ = locator.locate()
        #expect(lookUps.withLock { $0 } == 2)
    }
}
