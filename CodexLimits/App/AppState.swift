import AppKit
import Combine
import Foundation
import WebKit
import WidgetKit

@MainActor
final class AppState: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = AppState()

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var statusMessage: String
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoggedIn = false
    @Published private(set) var popupWebView: WKWebView?
    @Published private(set) var isMenuBarItemVisible: Bool
    @Published private(set) var showsPercentagesInMenuBar: Bool
    @Published private(set) var menuBarTextSize: MenuBarTextSize

    let webView: WKWebView

    private let fetcher = CodexUsageFetcher()
    private var refreshTask: Task<Void, Never>?
    private var snapshotSyncTask: Task<Void, Never>?
    private var pageIsReady = false

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let storedSnapshot = UsageSnapshotStore.load()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.snapshot = storedSnapshot
        self.statusMessage = storedSnapshot == nil
            ? String(localized: "content.notFetched")
            : String(localized: "status.updated")
        self.isMenuBarItemVisible = MenuBarSettings.isItemVisible
        self.showsPercentagesInMenuBar = MenuBarSettings.showsPercentages
        self.menuBarTextSize = MenuBarSettings.textSize
        super.init()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        webView.navigationDelegate = self
        webView.uiDelegate = self
        if let url = URL(string: "https://chatgpt.com/codex/cloud/settings/analytics#usage") {
            webView.load(URLRequest(url: url))
        }
        startAutoRefresh()
        startSnapshotSync()
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfiguration.widgetKind)
    }

    func refresh() async {
        guard pageIsReady, !isRefreshing else {
            if !pageIsReady {
                statusMessage = String(localized: "status.loadingLogin")
            }
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        let hasValidSession = await fetcher.hasValidSession(using: webView)
        isLoggedIn = hasValidSession
        guard hasValidSession else {
            statusMessage = String(localized: "content.notFetched")
            return
        }

        do {
            let newSnapshot = try await fetcher.fetch(using: webView)
            try UsageSnapshotStore.save(newSnapshot)
            snapshot = newSnapshot
            statusMessage = String(localized: "status.updated")
            WidgetCenter.shared.reloadTimelines(ofKind: AppConfiguration.widgetKind)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateRefreshInterval(_ minutes: Int) {
        RefreshIntervalSettings.save(minutes)
        startAutoRefresh()
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfiguration.widgetKind)
    }

    func updateShowsPercentagesInMenuBar(_ isVisible: Bool) {
        MenuBarSettings.saveShowsPercentages(isVisible)
        showsPercentagesInMenuBar = isVisible
    }

    func updateMenuBarItemVisibility(_ isVisible: Bool) {
        MenuBarSettings.saveItemVisibility(isVisible)
        isMenuBarItemVisible = isVisible
    }

    func updateMenuBarTextSize(_ size: MenuBarTextSize) {
        MenuBarSettings.saveTextSize(size)
        menuBarTextSize = size
    }

    func startAutoRefresh() {
        refreshTask?.cancel()
        let seconds = RefreshIntervalSettings.currentMinutes * 60
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    private func startSnapshotSync() {
        snapshotSyncTask?.cancel()
        snapshotSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.syncSnapshotFromSharedStore()
            }
        }
    }

    private func syncSnapshotFromSharedStore() {
        guard let storedSnapshot = UsageSnapshotStore.load() else { return }
        guard snapshot == nil || storedSnapshot.fetchedAt > snapshot!.fetchedAt else { return }
        snapshot = storedSnapshot
    }

    @objc private func handleSystemWake() {
        startAutoRefresh()
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfiguration.widgetKind)

        Task { [weak self] in
            await self?.refresh()
            try? await Task.sleep(for: .seconds(2))
            WidgetCenter.shared.reloadTimelines(ofKind: AppConfiguration.widgetKind)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === self.webView {
            pageIsReady = true
            Task { await refresh() }
        } else {
            Task {
                if await fetcher.hasValidSession(using: self.webView) {
                    closePopup()
                }
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        statusMessage = error.localizedDescription
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }

        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popupWebView = popup
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard webView === popupWebView else { return }
        closePopup()
    }

    func closePopup() {
        popupWebView?.navigationDelegate = nil
        popupWebView?.uiDelegate = nil
        popupWebView = nil
        Task { await refresh() }
    }
}
