import AppKit
import Observation
import SwiftUI
import UsageCore

/// Owns the menu bar item and its popover. Uses NSStatusItem rather than SwiftUI's MenuBarExtra
/// because MenuBarExtra draws its label in a single colour.
@MainActor
final class StatusItemController: NSObject {
    private let store: UsageStore
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    init(store: UsageStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let hosting = NSHostingController(rootView: DropdownView(store: store))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        observeStore()
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate()
            Task { await store.refresh() }
        }
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
