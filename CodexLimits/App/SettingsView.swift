import SwiftUI
import WebKit

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var refreshMinutes = RefreshIntervalSettings.currentMinutes
    @State private var isLoginExpanded = false

    var body: some View {
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

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isLoginExpanded.toggle()
                    }
                } label: {
                    Label {
                        Text(isLoginExpanded ? "Hide Login" : (state.isLoggedIn ? "Show Login" : "Sign In"))
                    } icon: {
                        Image(systemName: isLoginExpanded ? "chevron.up" : "chevron.down")
                    }
                }
            }

            if isLoginExpanded {
                CodexWebView(webView: state.webView)
                    .frame(minHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.quaternary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 520)
        .onChange(of: state.isLoggedIn) { _, isLoggedIn in
            guard isLoggedIn, isLoginExpanded else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
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

}

private struct CodexWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
