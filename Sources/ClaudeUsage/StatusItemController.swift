import AppKit
import Observation
import UsageCore

/// Owns the menu bar item. Uses NSStatusItem rather than SwiftUI's MenuBarExtra because
/// MenuBarExtra draws its label in a single colour.
@MainActor
final class StatusItemController: NSObject {
    private let store: UsageStore
    private let statusItem: NSStatusItem

    init(store: UsageStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        observeStore()
    }

    /// Re-renders whenever the store's limits or error change.
    private func observeStore() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStore() }
        }
    }

    private func render() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let title = NSMutableAttributedString()
        for segment in MenuBarLabel.segments(limits: store.limits, error: store.error) {
            title.append(NSAttributedString(
                string: segment.text,
                attributes: [.font: font, .foregroundColor: segment.level.nsColor]))
        }
        statusItem.button?.attributedTitle = title
        statusItem.button?.toolTip = MenuBarLabel.tooltip(limits: store.limits)
    }
}
