import Foundation
import Testing
@testable import UsageCore

/// Hands out scripted results in order (repeating the last one) and counts calls.
actor ScriptedFetch {
    private var results: [Result<String, UsageError>]
    private let delay: Duration
    private(set) var calls = 0

    init(_ results: [Result<String, UsageError>], delay: Duration = .zero) {
        self.results = results
        self.delay = delay
    }

    func next() async -> Result<String, UsageError> {
        calls += 1
        if delay > .zero { try? await Task.sleep(for: delay) }
        return results.count > 1 ? results.removeFirst() : results[0]
    }
}

@MainActor
@Suite struct UsageStoreTests {
    func makeStore(_ fetch: ScriptedFetch) -> UsageStore {
        UsageStore(fetch: { await fetch.next() })
    }

    @Test func successStoresLimits() async {
        let store = makeStore(ScriptedFetch([.success(Fixtures.usageOutput)]))
        await store.refresh()
        #expect(store.limits.map(\.shortName) == ["Session", "Week", "Fable"])
        #expect(store.error == nil)
        #expect(store.lastSuccess != nil)
        #expect(store.isRefreshing == false)
    }

    @Test func errorKeepsPreviousLimits() async {
        let store = makeStore(ScriptedFetch([.success(Fixtures.usageOutput), .failure(.timedOut)]))
        await store.refresh()
        let firstSuccess = store.lastSuccess
        await store.refresh()
        #expect(store.limits.count == 3)
        #expect(store.error == .timedOut)
        #expect(store.lastSuccess == firstSuccess)
    }

    @Test func successClearsError() async {
        let store = makeStore(ScriptedFetch([.failure(.timedOut), .success(Fixtures.usageOutput)]))
        await store.refresh()
        #expect(store.error == .timedOut)
        await store.refresh()
        #expect(store.error == nil)
    }

    @Test func unparseableOutputIsAnError() async {
        let store = makeStore(ScriptedFetch([.success("Something completely different\nsecond line")]))
        await store.refresh()
        #expect(store.limits.isEmpty)
        #expect(store.error == .unparseable(sample: "Something completely different\nsecond line"))
        #expect(store.lastSuccess == nil)
    }

    @Test func reportWithoutLimitsIsUnavailableNotUnparseable() async {
        let store = makeStore(ScriptedFetch([.success(Fixtures.usageOutput), .success(Fixtures.usageOutputWithoutLimits)]))
        await store.refresh()
        let firstSuccess = store.lastSuccess
        await store.refresh()
        #expect(store.limits.count == 3)
        #expect(store.error == .limitsUnavailable)
        #expect(store.lastSuccess == firstSuccess)
    }

    @Test func concurrentRefreshFetchesOnce() async {
        let fetch = ScriptedFetch([.success(Fixtures.usageOutput)], delay: .milliseconds(100))
        let store = makeStore(fetch)
        async let first: Void = store.refresh()
        async let second: Void = store.refresh()
        _ = await (first, second)
        #expect(await fetch.calls == 1)
    }

    @Test func autoRefreshRepeats() async throws {
        let fetch = ScriptedFetch([.success(Fixtures.usageOutput)])
        let store = makeStore(fetch)
        store.startAutoRefresh(interval: .milliseconds(50))
        try await Task.sleep(for: .milliseconds(300))
        store.stopAutoRefresh()
        #expect(await fetch.calls >= 2)
    }
}
