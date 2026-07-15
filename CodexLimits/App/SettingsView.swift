import AppKit
import SwiftUI
import WebKit

private enum DashboardTheme {
    static let backgroundTop = adaptive(
        light: nsColor(0.97, 0.995, 0.98),
        dark: nsColor(0.02, 0.11, 0.15)
    )
    static let backgroundBottom = adaptive(
        light: nsColor(0.84, 0.96, 0.90),
        dark: nsColor(0.005, 0.025, 0.04)
    )
    static let panelTop = adaptive(
        light: nsColor(1.00, 1.00, 1.00, 0.97),
        dark: nsColor(0.055, 0.18, 0.18, 0.98)
    )
    static let panelBottom = adaptive(
        light: nsColor(0.91, 0.97, 0.93, 0.97),
        dark: nsColor(0.025, 0.095, 0.12, 0.98)
    )
    static let panelStrongTop = adaptive(
        light: nsColor(0.95, 1.00, 0.97, 0.99),
        dark: nsColor(0.075, 0.22, 0.19, 0.99)
    )
    static let panelStrongBottom = adaptive(
        light: nsColor(0.84, 0.96, 0.89, 0.99),
        dark: nsColor(0.03, 0.12, 0.13, 0.99)
    )
    static let border = adaptive(
        light: nsColor(0.04, 0.34, 0.27, 0.24),
        dark: nsColor(0.18, 0.75, 0.66, 0.34)
    )
    static let text = adaptive(
        light: nsColor(0.02, 0.12, 0.14, 0.98),
        dark: nsColor(1.00, 1.00, 1.00, 0.98)
    )
    static let secondaryText = adaptive(
        light: nsColor(0.20, 0.34, 0.35, 0.72),
        dark: nsColor(0.72, 0.84, 0.82, 0.72)
    )
    static let accent = adaptive(
        light: nsColor(0.06, 0.76, 0.22),
        dark: nsColor(0.39, 0.95, 0.26)
    )
    static let warning = adaptive(
        light: nsColor(1.00, 0.49, 0.04),
        dark: nsColor(1.00, 0.58, 0.08)
    )
    static let danger = adaptive(
        light: nsColor(1.00, 0.10, 0.24),
        dark: nsColor(1.00, 0.20, 0.32)
    )

    static func metricColor(for remainingPercent: Double?) -> Color {
        guard let remainingPercent else { return secondaryText }
        switch UsageLevel.resolve(remainingPercent) {
        case .normal: return accent
        case .warning: return warning
        case .danger: return danger
        }
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? dark
                : light
        })
    }

    private static func nsColor(
        _ red: CGFloat,
        _ green: CGFloat,
        _ blue: CGFloat,
        _ alpha: CGFloat = 1
    ) -> NSColor {
        NSColor(
            calibratedRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }
}

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var state: AppState
    @State private var refreshMinutes = RefreshIntervalSettings.currentMinutes
    @State private var isLoginExpanded = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [DashboardTheme.backgroundTop, DashboardTheme.backgroundBottom]
                    : [Color.white, Color(nsColor: .windowBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Group {
                if isLoginExpanded {
                    loginContent
                } else {
                    settingsContent
                }
            }
            .padding(24)
        }
        .foregroundStyle(DashboardTheme.text)
        .tint(DashboardTheme.accent)
        .frame(
            minWidth: 680,
            maxWidth: .infinity,
            minHeight: 540,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .onChange(of: state.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn {
                isLoginExpanded = false
            }
        }
        .sheet(
            isPresented: Binding(
                get: { state.popupWebView != nil },
                set: { isPresented in
                    if !isPresented { state.closePopup() }
                }
            )
        ) {
            if let popupWebView = state.popupWebView {
                ZStack {
                    DashboardTheme.backgroundBottom.ignoresSafeArea()

                    VStack(spacing: 12) {
                        HStack {
                            Text("Complete sign in")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Spacer()
                            Button {
                                state.closePopup()
                            } label: {
                                Image(systemName: "xmark")
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(Color.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }

                        CodexWebView(webView: popupWebView)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(16)
                }
                .frame(minWidth: 600, minHeight: 700)
            }
        }
    }

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                dashboardHeader
                usageDashboard
                automationPanel
                menuBarPanel
                widgetPanel
                accountPanel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var dashboardHeader: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("CodexLimits")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))

                HStack(spacing: 7) {
                    Circle()
                        .fill(DashboardTheme.accent)
                        .frame(width: 7, height: 7)
                    Text("codex")
                        .foregroundStyle(DashboardTheme.accent)
                    Text("•")
                    Text("auto")
                    Text("•")
                    Text(updatedStatus)
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DashboardTheme.secondaryText)
            }

            Spacer(minLength: 16)
            refreshButton
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await state.refresh() }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Image(systemName: "arrow.clockwise")
                        .opacity(state.isRefreshing ? 0 : 1)
                    if state.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(DashboardTheme.accent)
                    }
                }
                .frame(width: 16, height: 16)

                Text(state.isRefreshing ? "Refreshing" : "Refresh")
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .frame(width: 112, height: 36)
            .background(
                Capsule()
                    .fill(DashboardTheme.accent.opacity(0.13))
            )
            .overlay {
                Capsule()
                    .stroke(DashboardTheme.accent.opacity(0.34), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(state.isRefreshing)
    }

    private var updatedStatus: String {
        if let fetchedAt = state.snapshot?.fetchedAt {
            return "updated \(fetchedAt.formatted(date: .omitted, time: .shortened))"
        }
        return state.statusMessage.lowercased()
    }

    private var usageDashboard: some View {
        VStack(spacing: 12) {
            usageCard(title: "5-hour window", window: state.snapshot?.primaryWindow)
            usageCard(title: "weekly window", window: state.snapshot?.secondaryWindow)
        }
    }

    private func usageCard(title: String, window: UsageWindow?) -> some View {
        let remainingPercent = window?.remainingPercent
        let metricColor = remainingPercent.map(DashboardTheme.metricColor)
            ?? DashboardTheme.secondaryText

        return VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(DashboardTheme.secondaryText)

                    Text(UsagePercentFormatter.format(remainingPercent))
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(metricColor)
                }

                Spacer()

                if let window, let reset = resetText(for: window) {
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("RESETS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(DashboardTheme.secondaryText)
                        Text(reset)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            progressBar(remainingPercent ?? 0, color: metricColor)
                .frame(height: 11)
        }
        .dashboardPanel(strong: true)
    }

    private var emptyUsageCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundStyle(DashboardTheme.secondaryText)

            VStack(alignment: .leading, spacing: 3) {
                Text("No usage data")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("Sign in to Codex to load the latest limit.")
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.secondaryText)
            }
            Spacer()
        }
        .dashboardPanel(strong: true)
    }

    private var automationPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Automatic refresh",
                subtitle: "Keep the menu bar and widgets current",
                symbol: "clock.arrow.circlepath"
            )

            HStack {
                Text("Update every")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DashboardTheme.secondaryText)

                Spacer()

                Picker("Update every", selection: $refreshMinutes) {
                    ForEach(RefreshIntervalSettings.options, id: \.self) { minutes in
                        Text("\(minutes)m").tag(minutes)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 230)
                .onChange(of: refreshMinutes) { _, value in
                    state.updateRefreshInterval(value)
                }
            }
        }
        .dashboardPanel()
    }

    private var menuBarPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Menu bar",
                subtitle: "Choose what stays visible at a glance",
                symbol: "menubar.rectangle"
            )

            HStack(spacing: 24) {
                Toggle(
                    "Show app",
                    isOn: Binding(
                        get: { state.isMenuBarItemVisible },
                        set: { state.updateMenuBarItemVisibility($0) }
                    )
                )
                .toggleStyle(.switch)

                Toggle(
                    "Show percentages",
                    isOn: Binding(
                        get: { state.showsPercentagesInMenuBar },
                        set: { state.updateShowsPercentagesInMenuBar($0) }
                    )
                )
                .toggleStyle(.switch)
                .disabled(!state.isMenuBarItemVisible)

                Spacer()
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))

            Rectangle()
                .fill(DashboardTheme.border)
                .frame(height: 1)

            HStack {
                Text("Text size")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DashboardTheme.secondaryText)

                Spacer()

                Picker(
                    "Text size",
                    selection: Binding(
                        get: { state.menuBarTextSize },
                        set: { state.updateMenuBarTextSize($0) }
                    )
                ) {
                    ForEach(MenuBarTextSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
                .disabled(!state.isMenuBarItemVisible)
            }
        }
        .dashboardPanel()
    }

    private var widgetPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Widget theme",
                subtitle: "Choose how limits are arranged on the desktop",
                symbol: "square.grid.2x2"
            )

            HStack(spacing: 16) {
                Text(
                    state.widgetLayoutStyle == .themeOne
                        ? "Clean card with a continuous progress bar"
                        : "Split reset card with segmented progress"
                )
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
                .lineLimit(1)

                Spacer(minLength: 12)

                Picker(
                    "Widget theme",
                    selection: Binding(
                        get: { state.widgetLayoutStyle },
                        set: { state.updateWidgetLayoutStyle($0) }
                    )
                ) {
                    ForEach(WidgetLayoutStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)
            }
        }
        .dashboardPanel()
    }

    private var accountPanel: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((state.isLoggedIn ? DashboardTheme.accent : DashboardTheme.warning).opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: state.isLoggedIn ? "checkmark" : "person.crop.circle")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(state.isLoggedIn ? DashboardTheme.accent : DashboardTheme.warning)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Codex account")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(state.isLoggedIn ? "Signed in" : "Sign in to fetch usage")
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.secondaryText)
            }

            Spacer()

            Button {
                state.reloadLoginPage()
                isLoginExpanded = true
            } label: {
                Label(
                    state.isLoggedIn ? "Manage login" : "Sign in",
                    systemImage: "arrow.up.right"
                )
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
                .overlay {
                    Capsule()
                        .stroke(DashboardTheme.border, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .dashboardPanel()
    }

    private var loginContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Codex sign in")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                    loginStatus
                }

                Spacer()

                Button {
                    state.reloadLoginPage()
                } label: {
                    Label("Reload page", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)

                Button {
                    isLoginExpanded = false
                } label: {
                    Label("Back to dashboard", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            CodexWebView(webView: state.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(DashboardTheme.border, lineWidth: 1)
                }
        }
    }

    private var loginStatus: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(state.isLoggedIn ? DashboardTheme.accent : DashboardTheme.warning)
                .frame(width: 7, height: 7)
            Text(state.isLoggedIn ? "Signed in" : "Authentication required")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DashboardTheme.secondaryText)
        }
    }

    private func sectionHeader(title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DashboardTheme.accent)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(DashboardTheme.accent.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.secondaryText)
            }
        }
    }

    private func progressBar(_ remainingPercent: Double, color: Color) -> some View {
        let normalized = CGFloat(max(0, min(100, remainingPercent)) / 100)

        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.72), color, color.opacity(0.92)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * normalized)
                    .shadow(color: color.opacity(0.34), radius: 4, x: 0, y: 1)
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

private extension View {
    func dashboardPanel(strong: Bool = false) -> some View {
        padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: strong
                                ? [DashboardTheme.panelStrongTop, DashboardTheme.panelStrongBottom]
                                : [DashboardTheme.panelTop, DashboardTheme.panelBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DashboardTheme.border, lineWidth: 1)
            }
    }
}

private struct CodexWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
