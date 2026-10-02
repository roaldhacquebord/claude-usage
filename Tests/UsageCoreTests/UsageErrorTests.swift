import Testing
@testable import UsageCore

@Suite struct UsageErrorTests {
    @Test func sampleKeepsFirstFiveNonEmptyLines() {
        #expect(UsageError.sample(of: "a\n\nb\n  c  \nd\ne\nf\n") == "a\nb\nc\nd\ne")
    }

    @Test func notFoundListsSearchedLocations() {
        let error = UsageError.notFound(searched: ["/a/claude", "/b/claude"])
        #expect(error.message == "Couldn't find the claude command")
        #expect(error.detail == "Looked in: /a/claude, /b/claude")
    }

    @Test func claudeErrorShowsClaudesMessage() {
        let error = UsageError.claudeError(message: "Login expired · run /login")
        #expect(error.message == "Login expired · run /login")
        #expect(error.detail == nil)
    }

    @Test func unparseableShowsSample() {
        let error = UsageError.unparseable(sample: "Something else")
        #expect(error.message == "Couldn't read usage; the /usage format may have changed")
        #expect(error.detail == "Something else")
    }

    @Test func limitsUnavailableSaysItWillRetry() {
        let error = UsageError.limitsUnavailable
        #expect(error.message == "Claude Code didn't return your limits; will retry")
        #expect(error.detail == nil)
    }
}
