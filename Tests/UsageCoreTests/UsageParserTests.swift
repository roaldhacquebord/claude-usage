import Testing
@testable import UsageCore

@Suite struct UsageParserTests {
    @Test func parsesRealOutput() {
        #expect(UsageParser.parse(Fixtures.usageOutput) == [
            Limit(label: "Current session", shortName: "Session", percent: 42, resetText: "resets Sep 12 at 12am"),
            Limit(label: "Current week (all models)", shortName: "Week", percent: 62, resetText: "resets Sep 13 at 9pm"),
            Limit(label: "Current week (Fable)", shortName: "Fable", percent: 93, resetText: "resets Sep 13 at 9pm"),
        ])
    }

    @Test func missingModelLimitIsSimplyAbsent() {
        let text = """
        Current session: 42% used · resets Sep 12 at 12am (Europe/Amsterdam)
        Current week (all models): 62% used · resets Sep 13 at 9pm (Europe/Amsterdam)
        """
        #expect(UsageParser.parse(text).map(\.shortName) == ["Session", "Week"])
    }

    @Test func extraLimitIsIncludedInOrder() {
        let text = Fixtures.usageOutput + "\nCurrent week (Sonnet): 10% used · resets Sep 14 at 1am (Europe/Amsterdam)"
        #expect(UsageParser.parse(text).map(\.shortName) == ["Session", "Week", "Fable", "Sonnet"])
    }

    @Test func rewordedOutputYieldsNoLimits() {
        let text = """
        Session usage: 42% (resets Sep 12)
        Weekly usage: 62%
        """
        #expect(UsageParser.parse(text).isEmpty)
    }

    @Test func decimalPercentage() {
        let limits = UsageParser.parse("Current session: 42.5% used · resets Sep 12 at 12am")
        #expect(limits.map(\.percent) == [42.5])
    }

    @Test func resetWithoutTimezoneIsKeptAsIs() {
        let limits = UsageParser.parse("Current session: 42% used · resets Sep 12 at 12am")
        #expect(limits.map(\.resetText) == ["resets Sep 12 at 12am"])
    }

    @Test(arguments: zip(["session", "week (all models)", "week (Fable)"], ["Session", "Week", "Fable"]))
    func shortNames(name: String, expected: String) {
        #expect(UsageParser.shortName(for: name) == expected)
    }
}
