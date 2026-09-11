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
    var barColor: Color {
        self == .normal ? .accentColor : Color(nsColor: nsColor)
    }
}
