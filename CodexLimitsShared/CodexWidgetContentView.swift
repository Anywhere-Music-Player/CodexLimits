import AppKit
import SwiftUI
import WidgetKit

private struct WidgetTheme {
    let backgroundTop: Color
    let backgroundBottom: Color
    let panelTop: Color
    let panelBottom: Color
    let border: Color
    let track: Color
    let text: Color
    let secondaryText: Color
    let accent: Color
    let warning: Color
    let danger: Color
    let usesSystemTint: Bool

    static func resolve(
        colorScheme: ColorScheme,
        renderingMode: WidgetRenderingMode
    ) -> WidgetTheme {
        switch renderingMode {
        case .fullColor:
            return colorScheme == .dark ? dark : light
        case .accented, .vibrant:
            return systemTint
        default:
            return colorScheme == .dark ? dark : light
        }
    }

    func metricColor(for remainingPercent: Double?) -> Color {
        guard let remainingPercent else { return secondaryText }
        let settings = UsageColorSettingsStore.current
        let level = UsageLevel.resolve(remainingPercent)
        let light = settings.resolvedColor(for: level, appearance: .light)
        let dark = settings.resolvedColor(for: level, appearance: .dark)

        return Color(nsColor: NSColor(name: nil) { appearance in
            let color = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? dark
                : light
            return NSColor(
                calibratedHue: color.hue,
                saturation: color.saturation,
                brightness: color.brightness,
                alpha: 1
            )
        })
    }

    private static let dark = WidgetTheme(
        backgroundTop: Color(red: 0.02, green: 0.11, blue: 0.15),
        backgroundBottom: Color(red: 0.005, green: 0.025, blue: 0.04),
        panelTop: Color(red: 0.055, green: 0.18, blue: 0.18),
        panelBottom: Color(red: 0.025, green: 0.095, blue: 0.12),
        border: Color(red: 0.18, green: 0.75, blue: 0.66).opacity(0.34),
        track: Color.white.opacity(0.12),
        text: Color.white.opacity(0.98),
        secondaryText: Color(red: 0.72, green: 0.84, blue: 0.82).opacity(0.76),
        accent: Color(red: 0.39, green: 0.95, blue: 0.26),
        warning: Color(red: 1.00, green: 0.58, blue: 0.08),
        danger: Color(red: 1.00, green: 0.20, blue: 0.32),
        usesSystemTint: false
    )

    private static let light = WidgetTheme(
        backgroundTop: Color(red: 0.97, green: 0.995, blue: 0.98),
        backgroundBottom: Color(red: 0.84, green: 0.96, blue: 0.90),
        panelTop: Color.white.opacity(0.98),
        panelBottom: Color(red: 0.91, green: 0.97, blue: 0.93),
        border: Color(red: 0.04, green: 0.34, blue: 0.27).opacity(0.24),
        track: Color(red: 0.02, green: 0.12, blue: 0.14).opacity(0.12),
        text: Color(red: 0.02, green: 0.12, blue: 0.14),
        secondaryText: Color(red: 0.20, green: 0.34, blue: 0.35).opacity(0.78),
        accent: Color(red: 0.06, green: 0.76, blue: 0.22),
        warning: Color(red: 1.00, green: 0.49, blue: 0.04),
        danger: Color(red: 1.00, green: 0.10, blue: 0.24),
        usesSystemTint: false
    )

    private static let systemTint = WidgetTheme(
        backgroundTop: .clear,
        backgroundBottom: .clear,
        panelTop: Color.primary.opacity(0.10),
        panelBottom: Color.primary.opacity(0.04),
        border: Color.primary.opacity(0.20),
        track: Color.primary.opacity(0.12),
        text: .primary,
        secondaryText: .secondary,
        accent: .primary,
        warning: .primary,
        danger: .primary,
        usesSystemTint: true
    )
}

enum CodexWidgetFamily {
    case small
    case medium
}

struct CodexWidgetContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    let snapshot: UsageSnapshot?
    let family: CodexWidgetFamily
    var style: WidgetLayoutStyle = WidgetLayoutStyleSettings.current
    var date: Date = Date()
    var usageStatus: UsageStatus = .ready

    private var theme: WidgetTheme {
        WidgetTheme.resolve(colorScheme: colorScheme, renderingMode: renderingMode)
    }

    private var windows: [UsageWindow] {
        [snapshot?.primaryWindow, snapshot?.secondaryWindow].compactMap { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if windows.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("No usage data").font(.headline)
                    Text(usageStatus == .failed ? String(localized: "Refresh failed") : String(localized: "Open CodexLimits to sign in")).font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else if windows.count == 1, let window = windows.first {
                featured(window)
                    .opacity(usageStatus.needsAttention ? 0.5 : 1)
            } else {
                VStack(spacing: family == .small ? 8 : 10) {
                    ForEach(windows, id: \.kind) { window in
                        compact(window)
                    }
                }
                .frame(maxHeight: .infinity)
                .opacity(usageStatus.needsAttention ? 0.5 : 1)
            }
        }
        .padding(.horizontal, family == .small ? 14 : 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(theme.text)
        .background {
            if !theme.usesSystemTint {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [theme.backgroundTop, theme.backgroundBottom]
                        : [Color.white, Color(white: 0.97)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Codex").font(.system(size: 17, weight: .bold, design: .rounded))
            Spacer(minLength: 4)
            if let message = usageStatus.message {
                Text("! \(message)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.usesSystemTint ? theme.text : Color.red)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel(message)
            } else if let fetchedAt = snapshot?.fetchedAt {
                Text(fetchedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    private func title(_ window: UsageWindow) -> String {
        window.kind == .primary ? String(localized: "5-Hour Limit") : String(localized: "Weekly Limit")
    }

    private func percentage(_ window: UsageWindow, size: CGFloat) -> some View {
        Text(UsagePercentFormatter.format(window.remainingPercent))
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(theme.metricColor(for: window.remainingPercent))
            .lineLimit(1).minimumScaleFactor(0.8)
            .widgetAccentable()
    }

    private func caption(_ window: UsageWindow) -> some View {
        Text(title(window))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.secondaryText)
            .lineLimit(1).minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private func featured(_ window: UsageWindow) -> some View {
        if family == .medium {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 18) {
                    if style == .ring {
                        ring(window, diameter: 94)
                        VStack(alignment: .leading, spacing: 9) {
                            caption(window)
                            reset(window)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            caption(window)
                            percentage(window, size: 42)
                        }
                        Spacer(minLength: 0)
                        reset(window)
                            .padding(10)
                            .background(theme.track.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(maxHeight: .infinity)
                if style != .ring { meter(window).frame(height: style == .themeTwo ? 18 : 7) }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                caption(window)
                if style == .ring {
                    ring(window, diameter: 62)
                        .frame(maxWidth: .infinity)
                } else {
                    percentage(window, size: 36)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    meter(window).frame(height: style == .themeTwo ? 12 : 5)
                }
                reset(window)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func compact(_ window: UsageWindow) -> some View {
        HStack(spacing: 10) {
            if style == .ring { ring(window, diameter: family == .small ? 40 : 48) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    caption(window)
                    if style != .ring {
                        Spacer(minLength: 3)
                        percentage(window, size: family == .small ? 19 : 23)
                    }
                }
                if family == .medium {
                    reset(window, compact: true)
                } else if let resetAt = window.resetAt {
                    Text(ResetCountdown.text(resetAt: resetAt, relativeTo: date))
                        .font(.system(size: 9)).foregroundStyle(theme.secondaryText)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                if style != .ring { meter(window).frame(height: 5) }
            }
        }
    }

    @ViewBuilder
    private func reset(_ window: UsageWindow, compact: Bool = false) -> some View {
        if let resetAt = window.resetAt {
            VStack(alignment: .leading, spacing: 3) {
                Text("Resets \(resetAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                    .font(.system(size: family == .small || compact ? 9 : 11, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(ResetCountdown.text(resetAt: resetAt, relativeTo: date))
                    .font(.system(size: family == .small || compact ? 9 : 11, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(theme.secondaryText)
        }
    }

    private func ring(_ window: UsageWindow, diameter: CGFloat) -> some View {
        ZStack {
            Circle().stroke(theme.track, lineWidth: diameter > 70 ? 8 : 5)
            Circle().trim(from: 0, to: window.remainingPercent / 100)
                .stroke(theme.metricColor(for: window.remainingPercent), style: StrokeStyle(
                    lineWidth: diameter > 70 ? 8 : 5, lineCap: .round
                ))
                .rotationEffect(.degrees(-90)).widgetAccentable()
            percentage(window, size: diameter > 70 ? 27 : diameter > 50 ? 20 : 11)
                .frame(width: diameter - 18)
        }
        .padding(4)
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title(window))
        .accessibilityValue(UsagePercentFormatter.format(window.remainingPercent))
    }

    private func meter(_ window: UsageWindow) -> some View {
        GeometryReader { geometry in
            let count = family == .small ? 12 : 24
            let gap: CGFloat = 3
            let segmentWidth = max(0, (geometry.size.width - CGFloat(count - 1) * gap) / CGFloat(count))
            ZStack(alignment: .leading) {
                if style == .themeTwo {
                    HStack(spacing: gap) {
                        ForEach(0..<count, id: \.self) { index in
                            let fraction = max(0, min(1, window.remainingPercent / 100 * Double(count) - Double(index)))
                            Capsule().fill(theme.track)
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(theme.metricColor(for: window.remainingPercent))
                                        .frame(width: segmentWidth * fraction).widgetAccentable()
                                }
                                .clipShape(Capsule())
                        }
                    }
                } else {
                    Capsule().fill(theme.track)
                    Capsule().fill(theme.metricColor(for: window.remainingPercent))
                        .frame(width: geometry.size.width * window.remainingPercent / 100)
                        .widgetAccentable()
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
private enum CodexWidgetPreviewData {
    static func snapshot(
        primaryRemaining: Double?,
        secondaryRemaining: Double?
    ) -> UsageSnapshot {
        UsageSnapshot(
            fetchedAt: Date(),
            primaryWindow: window(
                kind: .primary,
                remaining: primaryRemaining,
                resetInterval: 2.5 * 60 * 60,
                duration: 5 * 60 * 60
            ),
            secondaryWindow: window(
                kind: .secondary,
                remaining: secondaryRemaining,
                resetInterval: 5.5 * 24 * 60 * 60,
                duration: 7 * 24 * 60 * 60
            )
        )
    }

    private static func window(
        kind: UsageWindowKind,
        remaining: Double?,
        resetInterval: TimeInterval,
        duration: TimeInterval
    ) -> UsageWindow? {
        guard let remaining else { return nil }
        return UsageWindow(
            kind: kind,
            usedPercent: 100 - remaining,
            resetAt: Date().addingTimeInterval(resetInterval),
            limitWindowSeconds: duration
        )
    }
}

#Preview("Small - Green") {
    CodexWidgetContentView(
        snapshot: CodexWidgetPreviewData.snapshot(
            primaryRemaining: 88,
            secondaryRemaining: 72
        ),
        family: .small
    )
    .frame(width: 170, height: 170)
    .environment(\.colorScheme, .dark)
    .environment(\.widgetRenderingMode, .fullColor)
}

#Preview("Small - Orange") {
    CodexWidgetContentView(
        snapshot: CodexWidgetPreviewData.snapshot(
            primaryRemaining: 24,
            secondaryRemaining: 28
        ),
        family: .small
    )
    .frame(width: 170, height: 170)
    .environment(\.colorScheme, .dark)
    .environment(\.widgetRenderingMode, .fullColor)
}

#Preview("Small - Red") {
    CodexWidgetContentView(
        snapshot: CodexWidgetPreviewData.snapshot(
            primaryRemaining: 8,
            secondaryRemaining: 12
        ),
        family: .small
    )
    .frame(width: 170, height: 170)
    .environment(\.colorScheme, .dark)
    .environment(\.widgetRenderingMode, .fullColor)
}

#Preview("Medium - Mixed Dark") {
    CodexWidgetContentView(
        snapshot: CodexWidgetPreviewData.snapshot(
            primaryRemaining: 82,
            secondaryRemaining: 24
        ),
        family: .medium
    )
    .frame(width: 344, height: 170)
    .environment(\.colorScheme, .dark)
    .environment(\.widgetRenderingMode, .fullColor)
}

#Preview("Medium - Weekly Light") {
    CodexWidgetContentView(
        snapshot: CodexWidgetPreviewData.snapshot(
            primaryRemaining: nil,
            secondaryRemaining: 65
        ),
        family: .medium
    )
    .frame(width: 344, height: 170)
    .environment(\.colorScheme, .light)
    .environment(\.widgetRenderingMode, .fullColor)
}

#Preview("Medium - Accented") {
    CodexWidgetContentView(
        snapshot: CodexWidgetPreviewData.snapshot(
            primaryRemaining: 82,
            secondaryRemaining: 24
        ),
        family: .medium
    )
    .frame(width: 344, height: 170)
    .environment(\.colorScheme, .dark)
    .environment(\.widgetRenderingMode, .accented)
}

#Preview("Medium - Empty") {
    CodexWidgetContentView(
        snapshot: nil,
        family: .medium
    )
    .frame(width: 344, height: 170)
    .environment(\.colorScheme, .light)
    .environment(\.widgetRenderingMode, .fullColor)
}
#endif
