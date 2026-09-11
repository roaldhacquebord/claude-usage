import AppKit
import UsageCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore?
    private var statusItemController: StatusItemController?
    private var wakeObserver: NSObjectProtocol?
    private var loginItem: LoginItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = UsageStore(fetch: { await UsageFetcher().fetch() })
        self.store = store
        let loginItem = LoginItem()
        self.loginItem = loginItem
        loginItem.enableOnFirstLaunch()
        statusItemController = StatusItemController(store: store, loginItem: loginItem)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await store.refresh() }
        }
        store.startAutoRefresh()
    }
}
