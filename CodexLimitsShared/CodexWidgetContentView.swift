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

    private var theme: WidgetTheme {
        WidgetTheme.resolve(
            colorScheme: colorScheme,
            renderingMode: renderingMode
        )
    }

    private var layoutStyle: WidgetLayoutStyle {
        WidgetLayoutStyleSettings.current
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [theme.backgroundTop, theme.backgroundBottom]
                    : [Color.white, Color(white: 0.965)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Group {
                if layoutStyle == .themeTwo {
                    themeTwoContent
                } else {
                    switch family {
                    case .small:
                        smallContent
                    case .medium:
                        mediumContent
                    }
                }
            }
        }
        .foregroundStyle(theme.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var themeTwoContent: some View {
        switch family {
        case .small:
            themeTwoSmallContent
        case .medium:
            themeTwoMediumContent
        }
    }

    private var themeTwoSmallContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            header

            VStack(spacing: 12) {
                themeTwoCompactMeter(
                    title: "5-Hour Limit",
                    window: snapshot?.primaryWindow,
                    segments: 12
                )
                themeTwoCompactMeter(
                    title: "Weekly Limit",
                    window: snapshot?.secondaryWindow,
                    segments: 12
                )
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var themeTwoMediumContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            VStack(spacing: 16) {
                themeTwoCompactMeter(
                    title: "5-Hour Limit",
                    window: snapshot?.primaryWindow,
                    segments: 20
                )
                themeTwoCompactMeter(
                    title: "Weekly Limit",
                    window: snapshot?.secondaryWindow,
                    segments: 20
                )
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func themeTwoFeaturedSmall(title: String, window: UsageWindow) -> some View {
        let remainingPercent = window.remainingPercent
        let metricColor = theme.metricColor(for: remainingPercent)

        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)

            Text(UsagePercentFormatter.format(remainingPercent))
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(metricColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetAccentable()

            if let reset = resetText(for: window) {
                Label("Resets \(reset)", systemImage: "clock")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            segmentedProgress(remainingPercent, color: metricColor, segments: 12)
                .frame(height: 7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func themeTwoFeaturedMedium(title: String, window: UsageWindow) -> some View {
        let remainingPercent = window.remainingPercent
        let metricColor = theme.metricColor(for: remainingPercent)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)

                    Text(UsagePercentFormatter.format(remainingPercent))
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(metricColor)
                        .widgetAccentable()
                }

                Spacer(minLength: 8)

                if let reset = resetText(for: window) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("RESETS", systemImage: "clock")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(metricColor)

                        Text(reset)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .frame(minWidth: 142, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(colorScheme == .dark ? theme.panelTop : Color.white)
                    )
                }
            }

            segmentedProgress(remainingPercent, color: metricColor, segments: 20)
                .frame(height: 9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func themeTwoCompactMeter(
        title: String,
        window: UsageWindow?,
        segments: Int
    ) -> some View {
        let remainingPercent = window?.remainingPercent
        let metricColor = remainingPercent.map(theme.metricColor) ?? theme.secondaryText

        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(UsagePercentFormatter.format(remainingPercent))
                    .font(.system(size: family == .small ? 19 : 23, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(metricColor)
                    .widgetAccentable()
            }

            if let window, let reset = resetText(for: window) {
                Text("Resets \(reset)")
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            segmentedProgress(remainingPercent ?? 0, color: metricColor, segments: segments)
                .frame(height: family == .small ? 5 : 6)
        }
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            header

            panel(padding: 6, fillsHeight: true) {
                VStack(spacing: 12) {
                    compactMeter(title: "5-Hour Limit", window: snapshot?.primaryWindow)
                    compactMeter(title: "Weekly Limit", window: snapshot?.secondaryWindow)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            panel(padding: 8, fillsHeight: true) {
                VStack(spacing: 16) {
                    wideMeter(title: "5-Hour Limit", window: snapshot?.primaryWindow)
                    wideMeter(title: "Weekly Limit", window: snapshot?.secondaryWindow)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Codex")
                .font(.system(size: 17, weight: .heavy, design: .rounded))

            Spacer(minLength: 8)

            if let fetchedAt = snapshot?.fetchedAt {
                Text(fetchedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private func compactMeter(title: String, window: UsageWindow?) -> some View {
        let remainingPercent = window?.remainingPercent
        let metricColor = remainingPercent.map(theme.metricColor) ?? theme.secondaryText

        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)

                    if let window, let reset = resetText(for: window) {
                        Text("Resets \(reset)")
                            .font(.system(size: 7, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                Spacer(minLength: 4)

                Text(UsagePercentFormatter.format(remainingPercent))
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(metricColor)
                    .lineLimit(1)
                    .widgetAccentable()
            }

            progressBar(remainingPercent ?? 0, color: metricColor)
                .frame(height: 5)
        }
    }

    private func featuredSmall(title: String, window: UsageWindow) -> some View {
        let remainingPercent = window.remainingPercent
        let metricColor = theme.metricColor(for: remainingPercent)

        return panel(padding: 9, fillsHeight: true) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Text(UsagePercentFormatter.format(remainingPercent))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(metricColor)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .widgetAccentable()

                progressBar(remainingPercent, color: metricColor)
                    .frame(height: 7)

                if let reset = resetText(for: window) {
                    Text("Resets \(reset)")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
    }

    private func wideMeter(title: String, window: UsageWindow?) -> some View {
        let remainingPercent = window?.remainingPercent
        let metricColor = remainingPercent.map(theme.metricColor) ?? theme.secondaryText

        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(theme.secondaryText)

                    if let window, let reset = resetText(for: window) {
                        Text("Resets \(reset)")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(UsagePercentFormatter.format(remainingPercent))
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(metricColor)
                    .widgetAccentable()
            }

            progressBar(remainingPercent ?? 0, color: metricColor)
                .frame(height: 6)
        }
    }

    private func featuredMedium(title: String, window: UsageWindow) -> some View {
        let remainingPercent = window.remainingPercent
        let metricColor = theme.metricColor(for: remainingPercent)

        return panel(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(theme.secondaryText)

                        Text(UsagePercentFormatter.format(remainingPercent))
                            .font(.system(size: 42, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(metricColor)
                            .widgetAccentable()
                    }

                    Spacer()

                    if let reset = resetText(for: window) {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("RESETS")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .tracking(0.8)
                                .foregroundStyle(theme.secondaryText)
                            Text(reset)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                progressBar(remainingPercent, color: metricColor)
                    .frame(height: 8)
            }
        }
    }

    private var noDataView: some View {
        panel(padding: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(theme.secondaryText)
                Text("No usage data")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text("Open CodexLimits to sign in")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func panel<Content: View>(
        padding: CGFloat,
        fillsHeight: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(padding)
            .frame(
                maxWidth: .infinity,
                maxHeight: fillsHeight ? .infinity : nil,
                alignment: .leading
            )
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [theme.panelTop, theme.panelBottom]
                                : [Color.white, Color(white: 0.97)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private func progressBar(_ remainingPercent: Double, color: Color) -> some View {
        let normalized = CGFloat(max(0, min(100, remainingPercent)) / 100)

        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.track)
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * normalized)
                    .widgetAccentable()
            }
        }
    }

    private func segmentedProgress(
        _ remainingPercent: Double,
        color: Color,
        segments: Int
    ) -> some View {
        let normalized = max(0, min(100, remainingPercent)) / 100
        let activeSegments = normalized == 0
            ? 0
            : min(segments, Int(ceil(normalized * Double(segments))))

        return HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { index in
                Capsule()
                    .fill(index < activeSegments ? color : theme.track)
                    .widgetAccentable()
            }
        }
    }

    private func resetText(for window: UsageWindow) -> String? {
        guard let resetAt = window.resetAt else { return nil }
        if window.limitWindowSeconds >= 24 * 60 * 60 {
            return resetAt.formatted(
                .dateTime.month(.abbreviated).day().hour().minute()
            )
        }
        return resetAt.formatted(date: .omitted, time: .shortened)
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
