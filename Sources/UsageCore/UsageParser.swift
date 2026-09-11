import Foundation

/// Turns the human-readable text of Claude Code's `/usage` command into limits.
public enum UsageParser {
    /// Matches lines like `Current week (Fable): 93% used · resets Sep 13 at 9pm (Europe/Amsterdam)`
    /// and ignores everything else. Returns an empty array when nothing matches.
    public static func parse(_ text: String) -> [Limit] {
        text.split(whereSeparator: \.isNewline).compactMap { parseLine(String($0)) }
    }

    static func parseLine(_ line: String) -> Limit? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard
            let match = trimmed.wholeMatch(
                of: /Current (?<name>[^:]+): (?<percent>\d+(?:\.\d+)?)% used · (?<reset>resets .+)/),
            let percent = Double(match.output.percent)
        else { return nil }

        let name = String(match.output.name)
        return Limit(
            label: "Current \(name)",
            shortName: shortName(for: name),
            percent: percent,
            resetText: String(match.output.reset).replacing(/\s*\([^)]*\)$/, with: ""))
    }

    /// "week (Fable)" → "Fable", "week (all models)" → "Week", "session" → "Session".
    static func shortName(for name: String) -> String {
        if let match = name.firstMatch(of: /\((?<inner>[^)]+)\)/), match.output.inner != "all models" {
            return String(match.output.inner)
        }
        let firstWord = name.split(separator: " ").first.map(String.init) ?? name
        return firstWord.prefix(1).uppercased() + firstWord.dropFirst()
    }
}
