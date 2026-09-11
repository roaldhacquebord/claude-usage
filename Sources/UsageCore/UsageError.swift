import Foundation

/// Everything that can go wrong while getting usage, with the text the dropdown shows for it.
public enum UsageError: Error, Equatable, Sendable {
    case notFound(searched: [String])
    case claudeError(message: String)
    case timedOut
    case unreadableOutput(sample: String)
    /// The command succeeded but no usage lines were recognised. Set only by `UsageStore`.
    case unparseable(sample: String)

    public var message: String {
        switch self {
        case .notFound: "Couldn't find the claude command"
        case .claudeError(let message): message
        case .timedOut: "Claude Code didn't respond"
        case .unreadableOutput: "Couldn't read Claude Code's output"
        case .unparseable: "Couldn't read usage; the /usage format may have changed"
        }
    }

    public var detail: String? {
        switch self {
        case .notFound(let searched): "Looked in: " + searched.joined(separator: ", ")
        case .unreadableOutput(let sample), .unparseable(let sample): sample
        case .claudeError, .timedOut: nil
        }
    }

    /// The first few non-empty lines of `text`, for showing unexpected output.
    public static func sample(of text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(5)
            .joined(separator: "\n")
    }
}
