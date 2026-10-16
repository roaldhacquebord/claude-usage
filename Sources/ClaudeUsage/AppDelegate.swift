import AppKit
import UsageCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore?
    private var statusItemController: StatusItemController?
    private var powerObservers: [NSObjectProtocol] = []
    private var loginItem: LoginItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = UsageStore(fetch: { await UsageFetcher().fetch() })
        self.store = store
        let loginItem = LoginItem()
        self.loginItem = loginItem
        loginItem.enableOnFirstLaunch()
        statusItemController = StatusItemController(store: store, loginItem: loginItem)
        observePower(store: store)
        store.startAutoRefresh()
    }

    /// Stops polling while nobody can see the menu bar, and refreshes as soon as someone can again.
    /// System sleep and display sleep are both covered, since either can happen without the other.
    private func observePower(store: UsageStore) {
        let center = NSWorkspace.shared.notificationCenter
        let pauses: [Notification.Name] = [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification]
        let resumes: [Notification.Name] = [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification]
        for name in pauses {
            powerObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { store.stopAutoRefresh() }
            })
        }
        for name in resumes {
            // Waking usually posts both; the second restart finds a refresh running and skips it.
            powerObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { store.startAutoRefresh() }
            })
        }
    }
}
