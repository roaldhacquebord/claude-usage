import AppKit
import SwiftUI
import UsageCore

struct DropdownView: View {
    let store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = store.error {
                ErrorBanner(error: error)
            }
            if store.limits.isEmpty && store.error == nil {
                Text("Loading usage…").foregroundStyle(.secondary)
            }
            ForEach(store.limits, id: \.label) { limit in
                LimitRow(limit: limit, stale: store.error != nil)
            }
            Divider()
            HStack {
                TimelineView(.everyMinute) { context in
                    Text(footerText(now: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh now")
                }
            }
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 280)
    }

    private func footerText(now: Date) -> String {
        guard let lastSuccess = store.lastSuccess else { return "Not updated yet" }
        let relative = lastSuccess.formatted(
            .relative(presentation: .named).locale(Locale(identifier: "en_US")))
        return (store.error == nil ? "Updated " : "Last updated ") + relative
    }
}

private struct LimitRow: View {
    let limit: Limit
    let stale: Bool

    var body: some View {
        let level: Level = stale ? .stale : MenuBarLabel.level(for: limit.percent)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(limit.label).font(.callout.weight(.medium))
                Spacer()
                Text(MenuBarLabel.percentText(limit.percent)).monospacedDigit()
            }
            ProgressView(value: min(max(limit.percent, 0), 100), total: 100)
                .progressViewStyle(.linear)
                .tint(level.barColor)
            Text(limit.resetText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(stale ? .secondary : .primary)
    }
}

private struct ErrorBanner: View {
    let error: UsageError

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.orange)
            if let detail = error.detail {
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
        }
    }
}
