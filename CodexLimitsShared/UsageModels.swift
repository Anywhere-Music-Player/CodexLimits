import Foundation

enum AppConfiguration {
    static let appGroupIdentifier = "group.com.buildsucceeded.codex-limits"
    static let snapshotDirectory = "Library/Application Support/CodexLimits"
    static let snapshotFileName = "usage_snapshot.json"
    static let refreshIntervalKey = "usage_refresh_interval_minutes"
    static let menuBarItemVisibleKey = "menu_bar_item_visible"
    static let menuBarShowsPercentagesKey = "menu_bar_shows_percentages"
    static let menuBarTextSizeKey = "menu_bar_text_size"
    static let widgetLayoutStyleKey = "widget_layout_style"
    static let usageColorSettingsKey = "usage_color_settings_v1"
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

enum WidgetLayoutStyle: String, CaseIterable, Identifiable {
    case themeOne
    case themeTwo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .themeOne: return "Theme 1"
        case .themeTwo: return "Theme 2"
        }
    }
}

enum WidgetLayoutStyleSettings {
    static var current: WidgetLayoutStyle {
        guard let value = AppGroupDefaults.shared?.string(
            forKey: AppConfiguration.widgetLayoutStyleKey
        ) else {
            return .themeOne
        }
        return WidgetLayoutStyle(rawValue: value) ?? .themeOne
    }

    static func save(_ style: WidgetLayoutStyle) {
        AppGroupDefaults.shared?.set(
            style.rawValue,
            forKey: AppConfiguration.widgetLayoutStyleKey
        )
    }
}

enum UsageLevel: CaseIterable, Hashable {
    case normal
    case good
    case warning
    case low
    case danger

    static func resolve(_ remainingPercent: Double) -> UsageLevel {
        if remainingPercent <= 20 { return .danger }
        if remainingPercent <= 40 { return .low }
        if remainingPercent <= 60 { return .warning }
        if remainingPercent <= 80 { return .good }
        return .normal
    }
}

enum UsagePaletteAppearance: String, Codable {
    case light
    case dark
}

struct UsageHSBColor: Codable, Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double

    init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = Self.normalizedHue(hue)
        self.saturation = Self.clamped(saturation)
        self.brightness = Self.clamped(brightness)
    }

    init(red: Double, green: Double, blue: Double) {
        let maximum = max(red, max(green, blue))
        let minimum = min(red, min(green, blue))
        let delta = maximum - minimum
        let rawHue: Double

        if delta == 0 {
            rawHue = 0
        } else if maximum == red {
            rawHue = ((green - blue) / delta) / 6
        } else if maximum == green {
            rawHue = (((blue - red) / delta) + 2) / 6
        } else {
            rawHue = (((red - green) / delta) + 4) / 6
        }

        self.init(
            hue: rawHue,
            saturation: maximum == 0 ? 0 : delta / maximum,
            brightness: maximum
        )
    }

    func applying(
        hueShiftDegrees: Double,
        saturationAdjustment: Double,
        brightnessAdjustment: Double
    ) -> UsageHSBColor {
        UsageHSBColor(
            hue: hue + (hueShiftDegrees / 360),
            saturation: saturation + saturationAdjustment,
            brightness: brightness + brightnessAdjustment
        )
    }

    func removing(
        hueShiftDegrees: Double,
        saturationAdjustment: Double,
        brightnessAdjustment: Double
    ) -> UsageHSBColor {
        UsageHSBColor(
            hue: hue - (hueShiftDegrees / 360),
            saturation: saturation - saturationAdjustment,
            brightness: brightness - brightnessAdjustment
        )
    }

    private static func normalizedHue(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder < 0 ? remainder + 1 : remainder
    }

    private static func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

struct UsageColorPalette: Codable, Equatable {
    var normal: UsageHSBColor
    var good: UsageHSBColor
    var warning: UsageHSBColor
    var low: UsageHSBColor
    var danger: UsageHSBColor

    subscript(level: UsageLevel) -> UsageHSBColor {
        get {
            switch level {
            case .normal: return normal
            case .good: return good
            case .warning: return warning
            case .low: return low
            case .danger: return danger
            }
        }
        set {
            switch level {
            case .normal: normal = newValue
            case .good: good = newValue
            case .warning: warning = newValue
            case .low: low = newValue
            case .danger: danger = newValue
            }
        }
    }

    static let defaultLight = UsageColorPalette(
        normal: UsageHSBColor(red: 0.03, green: 0.58, blue: 0.21),
        good: UsageHSBColor(red: 0.36, green: 0.55, blue: 0.00),
        warning: UsageHSBColor(red: 0.96, green: 0.62, blue: 0.04),
        low: UsageHSBColor(red: 0.78, green: 0.29, blue: 0.04),
        danger: UsageHSBColor(red: 0.78, green: 0.16, blue: 0.16)
    )

    static let defaultDark = UsageColorPalette(
        normal: UsageHSBColor(red: 0.13, green: 0.77, blue: 0.37),
        good: UsageHSBColor(red: 0.52, green: 0.80, blue: 0.09),
        warning: UsageHSBColor(red: 0.96, green: 0.62, blue: 0.04),
        low: UsageHSBColor(red: 0.98, green: 0.45, blue: 0.09),
        danger: UsageHSBColor(red: 0.94, green: 0.27, blue: 0.27)
    )
}

struct UsageColorSettings: Codable, Equatable {
    var light: UsageColorPalette
    var dark: UsageColorPalette
    var hueShiftDegrees: Double
    var saturationAdjustment: Double
    var brightnessAdjustment: Double

    static let defaultValue = UsageColorSettings(
        light: .defaultLight,
        dark: .defaultDark,
        hueShiftDegrees: 0,
        saturationAdjustment: 0,
        brightnessAdjustment: 0
    )

    func resolvedColor(
        for level: UsageLevel,
        appearance: UsagePaletteAppearance
    ) -> UsageHSBColor {
        let base = appearance == .light ? light[level] : dark[level]
        return base.applying(
            hueShiftDegrees: hueShiftDegrees,
            saturationAdjustment: saturationAdjustment,
            brightnessAdjustment: brightnessAdjustment
        )
    }

    mutating func setResolvedColor(
        _ color: UsageHSBColor,
        for level: UsageLevel,
        appearance: UsagePaletteAppearance
    ) {
        let base = color.removing(
            hueShiftDegrees: hueShiftDegrees,
            saturationAdjustment: saturationAdjustment,
            brightnessAdjustment: brightnessAdjustment
        )
        switch appearance {
        case .light: light[level] = base
        case .dark: dark[level] = base
        }
    }
}

enum UsageColorSettingsStore {
    static var current: UsageColorSettings {
        guard let data = defaults.data(forKey: AppConfiguration.usageColorSettingsKey),
              let settings = try? JSONDecoder().decode(UsageColorSettings.self, from: data) else {
            return .defaultValue
        }
        return settings
    }

    static func save(_ settings: UsageColorSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: AppConfiguration.usageColorSettingsKey)
    }

    private static var defaults: UserDefaults {
        AppGroupDefaults.shared ?? .standard
    }
}

extension Notification.Name {
    static let usageColorSettingsDidChange = Notification.Name(
        "CodexLimits.usageColorSettingsDidChange"
    )
}

enum UsagePercentFormatter {
    static func format(_ percent: Double?) -> String {
        guard let percent else { return "--%" }
        return String(format: "%.0f%%", max(0, min(100, percent)))
    }
}
