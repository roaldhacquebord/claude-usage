import AppKit
import SwiftUI
import UsageCore

/// The usage panel hosted in the menu's custom-view item. Interactive controls live as real
/// NSMenuItems below it, so this view is display-only.
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
            TimelineView(.everyMinute) { context in
                Text(footerText(now: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let problem = loginItem.problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // Leading inset lines the text up with the menu item titles underneath.
        .padding(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 14))
        .frame(width: 250, alignment: .leading)
        .background(Color.clear)
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
/// while the menu's window isn't key (which it never is).
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
