/// One usage limit as reported by `/usage`, e.g. "Current week (Fable)" at 93%.
public struct Limit: Equatable, Sendable {
    public let label: String
    public let shortName: String
    public let percent: Double
    public let resetText: String

    public init(label: String, shortName: String, percent: Double, resetText: String) {
        self.label = label
        self.shortName = shortName
        self.percent = percent
        self.resetText = resetText
    }
}
