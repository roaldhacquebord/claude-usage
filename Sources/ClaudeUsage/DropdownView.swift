import AppKit
import SwiftUI
import UsageCore

struct DropdownView: View {
    let store: UsageStore
    let loginItem: LoginItem

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
            Toggle("Open at login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }))
                .toggleStyle(.checkbox)
            if let problem = loginItem.problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            UsageBar(percent: limit.percent, color: level.barColor)
            Text(limit.resetText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(stale ? .secondary : .primary)
    }
}

/// Drawn with shapes rather than `ProgressView`/`NSProgressIndicator`, which loses its tint colour
/// while the popover's window isn't key (e.g. for the entire open animation).
private struct UsageBar: View {
    let percent: Double
    let color: Color

    private var fraction: Double {
        min(max(percent, 0), 100) / 100
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 6)
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
