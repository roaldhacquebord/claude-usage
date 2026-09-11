import Testing
@testable import UsageCore

@Suite struct MenuBarLabelTests {
    let limits = UsageParser.parse(Fixtures.usageOutput) // 42, 62, 93

    @Test(arguments: zip([0, 79.9, 80, 94.9, 95, 100], [Level.normal, .normal, .warning, .warning, .critical, .critical]))
    func thresholds(percent: Double, expected: Level) {
        #expect(MenuBarLabel.level(for: percent) == expected)
    }

    @Test func percentTextRoundsDown() {
        #expect(MenuBarLabel.percentText(42) == "42%")
        #expect(MenuBarLabel.percentText(79.9) == "79%")
    }

    @Test func normalState() {
        let segments = MenuBarLabel.segments(limits: limits, error: nil)
        #expect(segments.map(\.text).joined() == "42% · 62% · 93%")
        #expect(segments.filter { $0.text.hasSuffix("%") }.map(\.level) == [.normal, .normal, .warning])
    }

    @Test func loadingState() {
        #expect(MenuBarLabel.segments(limits: [], error: nil) == [Segment(text: "\u{2013}", level: .normal)])
    }

    @Test func errorWithoutData() {
        #expect(MenuBarLabel.segments(limits: [], error: .timedOut)
            == [Segment(text: "\u{26A0}\u{FE0E}", level: .normal)])
    }

    @Test func errorWithStaleData() {
        let segments = MenuBarLabel.segments(limits: limits, error: .timedOut)
        #expect(segments.map(\.text).joined() == "\u{26A0}\u{FE0E} 42% · 62% · 93%")
        #expect(segments.allSatisfy { $0.level == .stale })
    }

    @Test func tooltip() {
        #expect(MenuBarLabel.tooltip(limits: limits) == "Session 42% · Week 62% · Fable 93%")
        #expect(MenuBarLabel.tooltip(limits: []) == "Claude usage")
    }
}
