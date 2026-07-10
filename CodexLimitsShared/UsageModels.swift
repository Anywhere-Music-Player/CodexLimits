import Foundation

enum AppConfiguration {
    static let appGroupIdentifier = "group.com.buildsucceeded.codex-limits"
    static let snapshotDirectory = "Library/Application Support/CodexLimits"
    static let snapshotFileName = "usage_snapshot.json"
    static let refreshIntervalKey = "usage_refresh_interval_minutes"
    static let menuBarItemVisibleKey = "menu_bar_item_visible"
    static let menuBarShowsPercentagesKey = "menu_bar_shows_percentages"
    static let menuBarTextSizeKey = "menu_bar_text_size"
    static let widgetKind = "CodexLimitsWidget"
    static let urlScheme = "codex-limits"
}

enum AppGroupDefaults {
    static var shared: UserDefaults? {
        UserDefaults(suiteName: AppConfiguration.appGroupIdentifier)
    }
}

enum UsageWindowKind: String, Codable {
    case primary
    case secondary
}

struct UsageWindow: Codable, Equatable {
    let kind: UsageWindowKind
    let usedPercent: Double
    let resetAt: Date?
    let limitWindowSeconds: TimeInterval

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }

    var isLongerThanWeekly: Bool {
        limitWindowSeconds > (7 * 24 * 60 * 60) + 1
    }
}

struct UsageSnapshot: Codable, Equatable {
    let fetchedAt: Date
    let primaryWindow: UsageWindow?
    let secondaryWindow: UsageWindow?
}

enum UsageSnapshotStore {
    static func load() -> UsageSnapshot? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    static func save(_ snapshot: UsageSnapshot) throws {
        guard let url = snapshotURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    private static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfiguration.appGroupIdentifier)?
            .appendingPathComponent(AppConfiguration.snapshotDirectory, isDirectory: true)
            .appendingPathComponent(AppConfiguration.snapshotFileName)
    }
}

enum RefreshIntervalSettings {
    static let options = [1, 2, 3, 5]
    static let defaultMinutes = 1

    static var currentMinutes: Int {
        let stored = AppGroupDefaults.shared?.integer(forKey: AppConfiguration.refreshIntervalKey) ?? 0
        return options.contains(stored) ? stored : defaultMinutes
    }

    static func save(_ minutes: Int) {
        let normalized = options.contains(minutes) ? minutes : defaultMinutes
        AppGroupDefaults.shared?.set(normalized, forKey: AppConfiguration.refreshIntervalKey)
    }
}

enum MenuBarTextSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var pointSize: Double {
        switch self {
        case .small: return 9
        case .medium: return 11
        case .large: return 13
        }
    }
}

enum MenuBarSettings {
    static var isItemVisible: Bool {
        guard let defaults = AppGroupDefaults.shared else { return true }
        guard defaults.object(forKey: AppConfiguration.menuBarItemVisibleKey) != nil else {
            return true
        }
        return defaults.bool(forKey: AppConfiguration.menuBarItemVisibleKey)
    }

    static var showsPercentages: Bool {
        guard let defaults = AppGroupDefaults.shared else { return true }
        guard defaults.object(forKey: AppConfiguration.menuBarShowsPercentagesKey) != nil else {
            return true
        }
        return defaults.bool(forKey: AppConfiguration.menuBarShowsPercentagesKey)
    }

    static var textSize: MenuBarTextSize {
        guard let value = AppGroupDefaults.shared?.string(forKey: AppConfiguration.menuBarTextSizeKey),
              let size = MenuBarTextSize(rawValue: value) else {
            return .large
        }
        return size
    }

    static func saveShowsPercentages(_ isVisible: Bool) {
        AppGroupDefaults.shared?.set(isVisible, forKey: AppConfiguration.menuBarShowsPercentagesKey)
    }

    static func saveItemVisibility(_ isVisible: Bool) {
        AppGroupDefaults.shared?.set(isVisible, forKey: AppConfiguration.menuBarItemVisibleKey)
    }

    static func saveTextSize(_ size: MenuBarTextSize) {
        AppGroupDefaults.shared?.set(size.rawValue, forKey: AppConfiguration.menuBarTextSizeKey)
    }
}

enum UsageLevel {
    case normal
    case warning
    case danger

    static func resolve(_ remainingPercent: Double) -> UsageLevel {
        if remainingPercent <= 20 { return .danger }
        if remainingPercent <= 40 { return .warning }
        return .normal
    }
}

enum UsagePercentFormatter {
    static func format(_ percent: Double?) -> String {
        guard let percent else { return "--%" }
        return String(format: "%.0f%%", max(0, min(100, percent)))
    }
}
