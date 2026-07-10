import SwiftUI
import WidgetKit

struct CodexLimitsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexLimitsEntry {
        CodexLimitsEntry(date: Date(), snapshot: Self.placeholderSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexLimitsEntry) -> Void) {
        completion(CodexLimitsEntry(
            date: Date(),
            snapshot: context.isPreview ? Self.placeholderSnapshot : UsageSnapshotStore.load()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexLimitsEntry>) -> Void) {
        let entry = CodexLimitsEntry(date: Date(), snapshot: UsageSnapshotStore.load())
        let widgetKitReloadMinutes = max(5, RefreshIntervalSettings.currentMinutes)
        let nextUpdate = Date().addingTimeInterval(
            TimeInterval(widgetKitReloadMinutes * 60)
        )
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
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
}

struct CodexLimitsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexLimitsEntry

    var body: some View {
        CodexWidgetContentView(
            snapshot: newestSnapshot(),
            family: family == .systemSmall ? .small : .medium
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
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Codex Limits")
        .description(String(localized: "widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
