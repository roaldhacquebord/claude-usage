/// How a percentage should be coloured.
public enum Level: Equatable, Sendable {
    case normal, warning, critical, stale
}

/// A run of menu bar text in one colour.
public struct Segment: Equatable, Sendable {
    public let text: String
    public let level: Level

    public init(text: String, level: Level) {
        self.text = text
        self.level = level
    }
}

/// What the menu bar shows, independent of AppKit so it can be tested.
public enum MenuBarLabel {
    static let separator = " · "
    static let loading = "\u{2013}"
    static let warningSign = "\u{26A0}\u{FE0E}"

    public static func level(for percent: Double) -> Level {
        if percent >= 95 { return .critical }
        if percent >= 80 { return .warning }
        return .normal
    }

    /// Rounded down, so the shown number never crosses a threshold before the colour does.
    public static func percentText(_ percent: Double) -> String {
        "\(Int(percent.rounded(.down)))%"
    }

    /// `42% · 62% · 93%`; `–` before the first result; `⚠︎` on error, followed by the
    /// previous numbers greyed out if there are any.
    public static func segments(limits: [Limit], error: UsageError?) -> [Segment] {
        guard !limits.isEmpty else {
            return [Segment(text: error == nil ? loading : warningSign, level: .normal)]
        }
        let stale = error != nil
        var result = stale ? [Segment(text: warningSign + " ", level: .stale)] : []
        for (index, limit) in limits.enumerated() {
            if index > 0 { result.append(Segment(text: separator, level: stale ? .stale : .normal)) }
            result.append(Segment(
                text: percentText(limit.percent),
                level: stale ? .stale : level(for: limit.percent)))
        }
        return result
    }

    public static func tooltip(limits: [Limit]) -> String {
        guard !limits.isEmpty else { return "Claude usage" }
        return limits.map { "\($0.shortName) \(percentText($0.percent))" }.joined(separator: separator)
    }
}
