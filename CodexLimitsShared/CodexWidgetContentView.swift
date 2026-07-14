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
        if usesSystemTint {
            return accent
        }
        switch UsageLevel.resolve(remainingPercent) {
        case .normal: return accent
        case .warning: return warning
        case .danger: return danger
        }
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

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.backgroundTop, theme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Group {
                switch family {
                case .small:
                    smallContent
                case .medium:
                    mediumContent
                }
            }
        }
        .foregroundStyle(theme.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            header

            if let primary = snapshot?.primaryWindow,
               let secondary = snapshot?.secondaryWindow {
                panel(padding: 7) {
                    VStack(spacing: 6) {
                        compactMeter(title: "5-Hour Limit", window: primary)
                        Rectangle()
                            .fill(theme.border)
                            .frame(height: 1)
                        compactMeter(title: "Weekly Limit", window: secondary)
                    }
                }
            } else if let primary = snapshot?.primaryWindow {
                featuredSmall(title: "5-Hour Limit", window: primary)
            } else if let secondary = snapshot?.secondaryWindow {
                featuredSmall(title: "Weekly Limit", window: secondary)
            } else {
                noDataView
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let primary = snapshot?.primaryWindow,
               let secondary = snapshot?.secondaryWindow {
                panel(padding: 8) {
                    VStack(spacing: 6) {
                        wideMeter(title: "5-Hour Limit", window: primary)
                        Rectangle()
                            .fill(theme.border)
                            .frame(height: 1)
                        wideMeter(title: "Weekly Limit", window: secondary)
                    }
                }
            } else if let primary = snapshot?.primaryWindow {
                featuredMedium(title: "5-Hour Limit", window: primary)
            } else if let secondary = snapshot?.secondaryWindow {
                featuredMedium(title: "Weekly Limit", window: secondary)
            } else {
                noDataView
            }
        }
        .padding(12)
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

    private func compactMeter(title: String, window: UsageWindow) -> some View {
        let remainingPercent = window.remainingPercent
        let metricColor = theme.metricColor(for: remainingPercent)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)

                    if let reset = resetText(for: window) {
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

            progressBar(remainingPercent, color: metricColor)
                .frame(height: 5)
        }
    }

    private func featuredSmall(title: String, window: UsageWindow) -> some View {
        let remainingPercent = window.remainingPercent
        let metricColor = theme.metricColor(for: remainingPercent)

        return panel(padding: 9) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(theme.secondaryText)

                        if let reset = resetText(for: window) {
                            Text("Resets \(reset)")
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Text(UsagePercentFormatter.format(remainingPercent))
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(metricColor)
                        .lineLimit(1)
                        .widgetAccentable()
                }

                progressBar(remainingPercent, color: metricColor)
                    .frame(height: 7)
            }
        }
    }

    private func wideMeter(title: String, window: UsageWindow) -> some View {
        let remainingPercent = window.remainingPercent
        let metricColor = theme.metricColor(for: remainingPercent)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(theme.secondaryText)

                    if let reset = resetText(for: window) {
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

            progressBar(remainingPercent, color: metricColor)
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
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [theme.panelTop, theme.panelBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
    }

    private func progressBar(_ remainingPercent: Double, color: Color) -> some View {
        let normalized = CGFloat(max(0, min(100, remainingPercent)) / 100)

        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.track)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.70), color, color.opacity(0.92)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * normalized)
                    .shadow(color: color.opacity(0.36), radius: 3, x: 0, y: 1)
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
