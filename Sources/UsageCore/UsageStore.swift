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
    @ObservationIgnored private var lastAttempt: ContinuousClock.Instant?

    public init(fetch: @escaping @Sendable () async -> Result<String, UsageError>) {
        self.fetch = fetch
    }

    /// Fetches and parses usage. Does nothing if a refresh is already running.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastAttempt = .now
        }

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

    /// Refreshes unless the last attempt, successful or not, finished less than `maxAge` ago.
    /// Each fetch runs `claude`, which costs seconds of CPU, so this throttles incidental refreshes.
    public func refreshIfStale(maxAge: Duration = .seconds(60)) async {
        if let lastAttempt, ContinuousClock.now - lastAttempt < maxAge { return }
        await refresh()
    }

    /// Refreshes now and then every `interval`, until `stopAutoRefresh()`.
    public func startAutoRefresh(interval: Duration = .seconds(300)) {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                // The slack lets macOS coalesce this wake-up with other timers.
                try? await Task.sleep(for: interval, tolerance: interval / 10)
            }
        }
    }

    public func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
}
