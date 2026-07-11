import SwiftUI
import WebKit

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var refreshMinutes = RefreshIntervalSettings.currentMinutes
    @State private var isLoginExpanded = false

    var body: some View {
        Group {
            if isLoginExpanded {
                loginContent
            } else {
                settingsContent
            }
        }
        .padding(20)
        .frame(
            minWidth: 560,
            maxWidth: .infinity,
            minHeight: 320,
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
                VStack(spacing: 8) {
                    HStack {
                        Spacer()
                        Button {
                            state.closePopup()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                    }
                    CodexWebView(webView: popupWebView)
                }
                .padding(12)
                .frame(minWidth: 600, minHeight: 700)
            }
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("CodexLimits")
                    .font(.largeTitle.bold())
                Spacer()
                Text(state.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text("refreshInterval.label")
                Picker("", selection: $refreshMinutes) {
                    ForEach(RefreshIntervalSettings.options, id: \.self) { minutes in
                        Text(String(
                            format: String(localized: "refreshInterval.minutesFormat"),
                            minutes
                        )).tag(minutes)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
                .onChange(of: refreshMinutes) { _, value in
                    state.updateRefreshInterval(value)
                }

                Button("content.refreshNow") {
                    Task { await state.refresh() }
                }
                .disabled(state.isRefreshing)

                if state.isRefreshing {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                if let fetchedAt = state.snapshot?.fetchedAt {
                    Text("\(String(localized: "usage.updated")) \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        "Show app in menu bar",
                        isOn: Binding(
                            get: { state.isMenuBarItemVisible },
                            set: { state.updateMenuBarItemVisibility($0) }
                        )
                    )

                    HStack(spacing: 16) {
                        Toggle(
                            "Show remaining percentages",
                            isOn: Binding(
                                get: { state.showsPercentagesInMenuBar },
                                set: { state.updateShowsPercentagesInMenuBar($0) }
                            )
                        )
                        .fixedSize()

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
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }
                    .disabled(!state.isMenuBarItemVisible)
                }
                .padding(4)
            } label: {
                Text("Menu Bar")
                    .font(.headline)
            }

            Divider()

            HStack {
                loginStatus
                Spacer()
                Button {
                    isLoginExpanded = true
                } label: {
                    Label(
                        state.isLoggedIn ? "Show Login" : "Sign In",
                        systemImage: "chevron.down"
                    )
                }
            }
        }
    }

    private var loginContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                loginStatus
                Spacer()
                Button {
                    isLoginExpanded = false
                } label: {
                    Label("Hide Login", systemImage: "chevron.up")
                }
            }

            CodexWebView(webView: state.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.quaternary)
                }
        }
    }

    private var loginStatus: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Login")
                .font(.headline)
            if state.isLoggedIn {
                Label("Signed in", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text("Open the browser only when you need to sign in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
