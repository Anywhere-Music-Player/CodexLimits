import AppKit
import SwiftUI
import WebKit
import WidgetKit

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

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case account

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var state: AppState
    @State private var refreshMinutes = RefreshIntervalSettings.currentMinutes
    @State private var isLoginExpanded = false
    @State private var selectedSection: SettingsSection = .general
    @State private var colorSettings = UsageColorSettingsStore.current

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
        .onDisappear {
            state.closeLoginPage()
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
                settingsTabs
                selectedSettingsContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var settingsTabs: some View {
        HStack {
            Spacer()
            Picker("Settings section", selection: $selectedSection) {
                ForEach(SettingsSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 420)
            Spacer()
        }
    }

    @ViewBuilder
    private var selectedSettingsContent: some View {
        switch selectedSection {
        case .general:
            automationPanel
        case .appearance:
            VStack(spacing: 14) {
                menuBarPanel
                widgetPanel
                colorSettingsPanel
            }
        case .account:
            accountPanel
        }
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
        HStack(spacing: 16) {
            sectionHeader(
                title: "Widget theme",
                subtitle: "Choose the widget appearance",
                symbol: "square.grid.2x2"
            )

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
        .dashboardPanel()
    }

    private var colorSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "Usage colors",
                subtitle: "Customize both appearances and tune every color together",
                symbol: "paintpalette"
            )

            HStack(alignment: .top, spacing: 12) {
                palettePreview(appearance: .light)
                palettePreview(appearance: .dark)
            }

            HStack(alignment: .top, spacing: 12) {
                paletteEditor(appearance: .light)
                paletteEditor(appearance: .dark)
            }

            Rectangle()
                .fill(DashboardTheme.border)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Global HSB adjustment")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Text("Applies to every light and dark color")
                            .font(.caption)
                            .foregroundStyle(DashboardTheme.secondaryText)
                    }
                    Spacer()
                    Button("Reset HSB") {
                        var updated = colorSettings
                        updated.hueShiftDegrees = 0
                        updated.saturationAdjustment = 0
                        updated.brightnessAdjustment = 0
                        applyColorSettings(updated)
                    }
                    .buttonStyle(.bordered)
                }

                hsbSlider(
                    title: "Hue",
                    value: adjustmentBinding(\.hueShiftDegrees),
                    range: -180...180,
                    step: 1,
                    valueText: "\(Int(colorSettings.hueShiftDegrees.rounded()))°"
                )
                hsbSlider(
                    title: "Saturation",
                    value: adjustmentBinding(\.saturationAdjustment),
                    range: -0.5...0.5,
                    step: 0.01,
                    valueText: String(format: "%+.0f%%", colorSettings.saturationAdjustment * 100)
                )
                hsbSlider(
                    title: "Brightness",
                    value: adjustmentBinding(\.brightnessAdjustment),
                    range: -0.5...0.5,
                    step: 0.01,
                    valueText: String(format: "%+.0f%%", colorSettings.brightnessAdjustment * 100)
                )
            }

            HStack {
                Spacer()
                Button("Reset All Colors") {
                    applyColorSettings(.defaultValue)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .dashboardPanel()
    }

    private func palettePreview(appearance: UsagePaletteAppearance) -> some View {
        let isDark = appearance == .dark

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isDark ? "Dark preview" : "Light preview")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text("45%")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(usageColor(for: .warning, appearance: appearance))
            }

            ForEach(UsageLevel.allCases, id: \.self) { level in
                HStack(spacing: 8) {
                    Text(levelRange(level))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .frame(width: 48, alignment: .leading)
                        .opacity(0.68)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.09))
                            Capsule()
                                .fill(usageColor(for: level, appearance: appearance))
                                .frame(width: geometry.size.width * previewAmount(level))
                        }
                    }
                    .frame(height: 8)
                }
                .frame(height: 14)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .foregroundStyle(isDark ? Color.white : Color(red: 0.02, green: 0.12, blue: 0.14))
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isDark ? Color(red: 0.02, green: 0.11, blue: 0.15) : Color.white)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.10), lineWidth: 1)
        }
    }

    private func paletteEditor(appearance: UsagePaletteAppearance) -> some View {
        let title = appearance == .light ? "Light colors" : "Dark colors"

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Button("Reset") {
                    var updated = colorSettings
                    if appearance == .light {
                        updated.light = .defaultLight
                    } else {
                        updated.dark = .defaultDark
                    }
                    applyColorSettings(updated)
                }
                .buttonStyle(.borderless)
            }

            ForEach(UsageLevel.allCases, id: \.self) { level in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(levelTitle(level))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Text(levelRange(level))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(DashboardTheme.secondaryText)
                    }
                    Spacer()
                    ColorPicker(
                        levelTitle(level),
                        selection: colorBinding(for: level, appearance: appearance),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .frame(width: 30)
                }
                .frame(height: 28)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DashboardTheme.panelTop.opacity(0.62))
        )
    }

    private func hsbSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(width: 76, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(valueText)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func usageColor(
        for level: UsageLevel,
        appearance: UsagePaletteAppearance
    ) -> Color {
        let color = colorSettings.resolvedColor(for: level, appearance: appearance)
        return Color(
            hue: color.hue,
            saturation: color.saturation,
            brightness: color.brightness
        )
    }

    private func colorBinding(
        for level: UsageLevel,
        appearance: UsagePaletteAppearance
    ) -> Binding<Color> {
        Binding(
            get: { usageColor(for: level, appearance: appearance) },
            set: { newColor in
                guard let converted = NSColor(newColor).usingColorSpace(.deviceRGB) else { return }
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                converted.getHue(
                    &hue,
                    saturation: &saturation,
                    brightness: &brightness,
                    alpha: &alpha
                )

                var updated = colorSettings
                updated.setResolvedColor(
                    UsageHSBColor(
                        hue: Double(hue),
                        saturation: Double(saturation),
                        brightness: Double(brightness)
                    ),
                    for: level,
                    appearance: appearance
                )
                applyColorSettings(updated)
            }
        )
    }

    private func adjustmentBinding(
        _ keyPath: WritableKeyPath<UsageColorSettings, Double>
    ) -> Binding<Double> {
        Binding(
            get: { colorSettings[keyPath: keyPath] },
            set: { value in
                var updated = colorSettings
                updated[keyPath: keyPath] = value
                applyColorSettings(updated)
            }
        )
    }

    private func applyColorSettings(_ settings: UsageColorSettings) {
        colorSettings = settings
        UsageColorSettingsStore.save(settings)
        NotificationCenter.default.post(name: .usageColorSettingsDidChange, object: nil)
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfiguration.widgetKind)
    }

    private func levelTitle(_ level: UsageLevel) -> String {
        switch level {
        case .normal: return "Healthy"
        case .good: return "Good"
        case .warning: return "Attention"
        case .low: return "Low"
        case .danger: return "Critical"
        }
    }

    private func levelRange(_ level: UsageLevel) -> String {
        switch level {
        case .normal: return "81–100"
        case .good: return "61–80"
        case .warning: return "41–60"
        case .low: return "21–40"
        case .danger: return "0–20"
        }
    }

    private func previewAmount(_ level: UsageLevel) -> Double {
        switch level {
        case .normal: return 0.90
        case .good: return 0.70
        case .warning: return 0.50
        case .low: return 0.30
        case .danger: return 0.10
        }
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
                    state.closeLoginPage()
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

            if let loginWebView = state.loginWebView {
                CodexWebView(webView: loginWebView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(DashboardTheme.border, lineWidth: 1)
                    }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

}

private extension View {
    func dashboardPanel() -> some View {
        padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [DashboardTheme.panelTop, DashboardTheme.panelBottom],
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
