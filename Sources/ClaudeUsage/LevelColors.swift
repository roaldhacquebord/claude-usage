import AppKit
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
}
