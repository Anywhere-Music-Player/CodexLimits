import AppIntents
import SwiftUI
import WidgetKit

struct ReloadCodexLimitsWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Codex Limits"
    static var description = IntentDescription(
        "Fetches the latest Codex usage and reloads the widget."
    )
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        WidgetRefreshState.request()
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfiguration.widgetKind)
        return .result()
    }
}

enum CodexWidgetFamily {
    case small
    case medium
}

struct CodexWidgetContentView: View {
    let snapshot: UsageSnapshot?
    let family: CodexWidgetFamily

    var body: some View {
        Group {
            switch family {
            case .small:
                smallContent
            case .medium:
                mediumContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let snapshot {
                VStack(spacing: 10) {
                    compactMeter(
                        title: "5-Hour Limit",
                        window: snapshot.primaryWindow
                    )
                    compactMeter(
                        title: "Weekly Limit",
                        window: snapshot.secondaryWindow
                    )
                }
            } else {
                noDataView
            }
        }
        .padding(12)
    }

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let snapshot {
                VStack(spacing: 6) {
                    mediumMeter(
                        title: "5-Hour Limit",
                        window: snapshot.primaryWindow
                    )

                    Divider()
                        .opacity(0.45)

                    mediumMeter(
                        title: "Weekly Limit",
                        window: snapshot.secondaryWindow
                    )
                }
            } else {
                noDataView
            }
        }
        .padding(14)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Codex")
                .font(.headline.bold())
            Spacer()

            if WidgetRefreshState.isRefreshing {
                if let fetchedAt = snapshot?.fetchedAt {
                    Text(fetchedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 18, height: 18)
                    .accessibilityLabel("Refreshing")
            } else {
                Button(intent: ReloadCodexLimitsWidgetIntent()) {
                    HStack(spacing: 8) {
                        if let fetchedAt = snapshot?.fetchedAt {
                            Text(fetchedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2.weight(.semibold))
                            .frame(width: 18, height: 18)
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(-12)
                .accessibilityLabel("Refresh Widget")
            }
        }
    }

    private func compactMeter(title: String, window: UsageWindow?) -> some View {
        let remainingPercent = window?.remainingPercent
        return VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)

                Spacer(minLength: 4)

                Text(UsagePercentFormatter.format(remainingPercent))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color(for: remainingPercent))
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            progressBar(remainingPercent)
                .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
    }

    private func mediumMeter(title: String, window: UsageWindow?) -> some View {
        let remainingPercent = window?.remainingPercent
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(UsagePercentFormatter.format(remainingPercent))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color(for: remainingPercent))
                    .lineLimit(1)
            }

            progressBar(remainingPercent)
                .frame(height: 5)

            if let resetText = resetText(for: window) {
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressBar(_ remainingPercent: Double?) -> some View {
        let normalized = CGFloat(max(0, min(100, remainingPercent ?? 0)) / 100)
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                Capsule()
                    .fill(color(for: remainingPercent))
                    .frame(width: geometry.size.width * normalized)
            }
        }
    }

    private func resetText(for window: UsageWindow?) -> String? {
        guard let window, let resetAt = window.resetAt else { return nil }
        if window.limitWindowSeconds >= 24 * 60 * 60 {
            let date = resetAt.formatted(
                .dateTime.month(.abbreviated).day().hour().minute()
            )
            return "Resets \(date)"
        }
        return "Resets \(resetAt.formatted(date: .omitted, time: .shortened))"
    }

    private var noDataView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Not fetched")
            Text("Open CodexLimits to sign in")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func color(for remainingPercent: Double?) -> Color {
        guard let remainingPercent else { return .secondary }
        switch UsageLevel.resolve(remainingPercent) {
        case .normal: return .green
        case .warning: return .orange
        case .danger: return .red
        }
    }
}
