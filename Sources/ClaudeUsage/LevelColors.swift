import AppKit
import SwiftUI
import UsageCore

extension Level {
    var nsColor: NSColor {
        switch self {
        case .normal: .labelColor
        case .warning: .systemOrange
        case .critical: .systemRed
        case .stale: .secondaryLabelColor
        }
    }

    /// Progress bars use the accent colour when normal; the menu bar uses the plain text colour.
    /// Both are resolved via `NSColor` deliberately: they must not depend on the popover's window
    /// being key, unlike SwiftUI's `.accentColor`/`.tint`.
    var barColor: Color {
        self == .normal ? Color(nsColor: .controlAccentColor) : Color(nsColor: nsColor)
    }
}
