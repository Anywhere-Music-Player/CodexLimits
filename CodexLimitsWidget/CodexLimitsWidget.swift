import SwiftUI
import WidgetKit

struct CodexLimitsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexLimitsEntry {
        CodexLimitsEntry(date: Date(), snapshot: Self.placeholderSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexLimitsEntry) -> Void) {
        completion(CodexLimitsEntry(
            date: Date(),
            snapshot: context.isPreview ? Self.placeholderSnapshot : UsageSnapshotStore.load(),
            usageStatus: context.isPreview ? .ready : UsageStatusStore.load(hasSnapshot: UsageSnapshotStore.load() != nil)
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexLimitsEntry>) -> Void) {
        let now = Date()
        let snapshot = UsageSnapshotStore.load()
        let status = UsageStatusStore.load(hasSnapshot: snapshot != nil)
        let widgetKitReloadMinutes = max(5, RefreshIntervalSettings.currentMinutes)
        let nextUpdate = now.addingTimeInterval(
            TimeInterval(widgetKitReloadMinutes * 60)
        )
        // Precomputed entries keep reset countdowns moving even when WidgetKit defers a reload.
        let dates = (0...60).map { now.addingTimeInterval(TimeInterval($0 * 60)) }
        let resets = [snapshot?.primaryWindow?.resetAt, snapshot?.secondaryWindow?.resetAt]
            .compactMap { $0 }.filter { $0 > now && $0 < now.addingTimeInterval(3600) }
        let entries = Set(dates + resets).sorted().map { CodexLimitsEntry(date: $0, snapshot: snapshot, usageStatus: status) }
        completion(Timeline(entries: entries, policy: .after(nextUpdate)))
    }

    private static let placeholderSnapshot = UsageSnapshot(
        fetchedAt: Date(),
        primaryWindow: UsageWindow(
            kind: .primary,
            usedPercent: 28,
            resetAt: Date().addingTimeInterval(3 * 60 * 60),
            limitWindowSeconds: 5 * 60 * 60
        ),
        secondaryWindow: UsageWindow(
            kind: .secondary,
            usedPercent: 34,
            resetAt: Date().addingTimeInterval(6 * 24 * 60 * 60),
            limitWindowSeconds: 7 * 24 * 60 * 60
        )
    )
}

struct CodexLimitsEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    var usageStatus: UsageStatus = .ready
}

struct CodexLimitsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexLimitsEntry

    var body: some View {
        CodexWidgetContentView(
            snapshot: newestSnapshot(),
            family: family == .systemSmall ? .small : .medium,
            date: entry.date,
            usageStatus: entry.usageStatus
        )
        .widgetURL(URL(string: "codex-limits://open-settings"))
    }

    private func newestSnapshot() -> UsageSnapshot? {
        let storedSnapshot = UsageSnapshotStore.load()
        guard let entrySnapshot = entry.snapshot else { return storedSnapshot }
        guard let storedSnapshot else { return entrySnapshot }
        return storedSnapshot.fetchedAt > entrySnapshot.fetchedAt
            ? storedSnapshot
            : entrySnapshot
    }
}

struct CodexLimitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: AppConfiguration.widgetKind,
            provider: CodexLimitsTimelineProvider()
        ) { entry in
            CodexLimitsWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("Codex Limits")
        .description(String(localized: "widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
