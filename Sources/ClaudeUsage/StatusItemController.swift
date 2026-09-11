import AppKit
import Observation
import SwiftUI
import UsageCore

/// Owns the menu bar item and its menu. Uses NSStatusItem rather than SwiftUI's MenuBarExtra
/// because MenuBarExtra draws its label in a single colour.
///
/// The dropdown is a real NSMenu with the usage panel hosted in a custom-view item, so it gets the
/// system's menu material, corner radius and highlight rather than a popover's panel look.
@MainActor
final class StatusItemController: NSObject {
    private let store: UsageStore
    private let loginItem: LoginItem
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let refreshItem = NSMenuItem(
        title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "")
    private let loginMenuItem = NSMenuItem(
        title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
    private var panelView: NSHostingView<DropdownView>?

    init(store: UsageStore, loginItem: LoginItem) {
        self.store = store
        self.loginItem = loginItem
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        buildMenu(loginItem: loginItem)
        statusItem.menu = menu
        observeStore()
    }

    private func buildMenu(loginItem: LoginItem) {
        // No responder chain to validate against, so items manage their own enabled state.
        menu.autoenablesItems = false
        menu.delegate = self

        let panel = NSMenuItem()
        let hosting = NSHostingView(rootView: DropdownView(store: store, loginItem: loginItem))
        // The panel grows as limits load in, so let SwiftUI keep the intrinsic size current
        // instead of freezing the frame at whatever fits the "Loading usage…" placeholder.
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        panelView = hosting
        panel.view = hosting
        menu.addItem(panel)

        menu.addItem(.separator())

        refreshItem.target = self
        menu.addItem(refreshItem)

        loginMenuItem.target = self
        menu.addItem(loginMenuItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    @objc private func refreshNow() {
        Task { await store.refresh() }
    }

    @objc private func toggleLoginItem() {
        loginItem.setEnabled(!loginItem.isEnabled)
        syncMenuItems()
    }

    private func syncMenuItems() {
        if let panelView {
            panelView.frame.size = panelView.fittingSize
        }
        refreshItem.isEnabled = !store.isRefreshing
        refreshItem.title = store.isRefreshing ? "Refreshing…" : "Refresh Now"
        loginMenuItem.state = loginItem.isEnabled ? .on : .off
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
        syncMenuItems()
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        syncMenuItems()
        Task { await store.refresh() }
    }
}
