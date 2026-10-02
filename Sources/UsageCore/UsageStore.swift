import Foundation
import Observation

/// The app's usage state. On failure it keeps the last good limits so the UI can show them as stale.
@MainActor
@Observable
public final class UsageStore {
    public private(set) var limits: [Limit] = []
    public private(set) var lastSuccess: Date?
    public private(set) var error: UsageError?
    public private(set) var isRefreshing = false

    private let fetch: @Sendable () async -> Result<String, UsageError>
    @ObservationIgnored private var autoRefreshTask: Task<Void, Never>?

    public init(fetch: @escaping @Sendable () async -> Result<String, UsageError>) {
        self.fetch = fetch
    }

    /// Fetches and parses usage. Does nothing if a refresh is already running.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        switch await fetch() {
        case .success(let text):
            let parsed = UsageParser.parse(text)
            if parsed.isEmpty {
                error = UsageParser.isUsageReport(text)
                    ? .limitsUnavailable : .unparseable(sample: UsageError.sample(of: text))
            } else {
                limits = parsed
                lastSuccess = Date()
                error = nil
            }
        case .failure(let failure):
            error = failure
        }
    }

    /// Refreshes now and then every `interval`, until `stopAutoRefresh()`.
    public func startAutoRefresh(interval: Duration = .seconds(300)) {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
}
