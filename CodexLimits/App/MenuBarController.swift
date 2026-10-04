import AppKit
import Combine

private final class MenuBarTextStackView: NSStackView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let state: AppState
    private let statusItem: NSStatusItem
    private let percentagesLabel = NSTextField(labelWithString: "")
    private let updatedAtLabel = NSTextField(labelWithString: "")
    private let textStack = MenuBarTextStackView()
    private var cancellables: Set<AnyCancellable> = []

    init(state: AppState) {
        self.state = state
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.isVisible = state.isMenuBarItemVisible
        configureButtonContent()
        configureMenu()
        updateTitle(state.snapshot)

        NotificationCenter.default.publisher(for: .usageColorSettingsDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateTitle(self.state.snapshot)
            }
            .store(in: &cancellables)

        state.$usageStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateTitle(self.state.snapshot)
            }
            .store(in: &cancellables)

        state.$showsProgressInMenuBar
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                self.updateTitle(self.state.snapshot, showsProgress: value)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            state.$snapshot,
            state.$isMenuBarItemVisible,
            state.$showsPercentagesInMenuBar,
            state.$menuBarTextSize
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] values in
                self?.statusItem.isVisible = values.1
                self?.updateTitle(values.0)
            }
            .store(in: &cancellables)
    }

    private func configureButtonContent() {
        guard let button = statusItem.button else { return }

        percentagesLabel.alignment = .center
        updatedAtLabel.alignment = .center
        percentagesLabel.setContentHuggingPriority(.required, for: .horizontal)
        updatedAtLabel.setContentHuggingPriority(.required, for: .horizontal)
        percentagesLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        updatedAtLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        textStack.orientation = .vertical
        textStack.alignment = .centerX
        textStack.distribution = .fill
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(percentagesLabel)
        textStack.addArrangedSubview(updatedAtLabel)
        textStack.isHidden = true

        button.addSubview(textStack)
        NSLayoutConstraint.activate([
            textStack.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            textStack.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.delegate = self
        populateMenu(menu)
        statusItem.menu = menu
    }

    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        MenuBarPresentation.resetCreditsSection(
            resetCredits: state.snapshot?.resetCredits,
            usageStatus: state.usageStatus,
            date: Date()
        ).forEach { menu.addItem($0) }
        menu.addItem(makeItem(
            String(localized: "content.refreshNow"),
            systemImage: "arrow.clockwise",
            action: #selector(refreshNow)
        ))
        menu.addItem(makeItem(
            String(localized: "menu.openSettings"),
            systemImage: "gearshape",
            action: #selector(openSettings)
        ))
        menu.addItem(.separator())
        menu.addItem(makeItem(
            String(localized: "menu.quit"),
            action: #selector(quit)
        ))
        menu.items.forEach { $0.target = self }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Recalculate on every opening, including credits that expired between refreshes.
        populateMenu(menu)
    }

    private func makeItem(
        _ title: String,
        systemImage: String? = nil,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        if let systemImage {
            item.image = NSImage(
                systemSymbolName: systemImage,
                accessibilityDescription: title
            )
        }
        return item
    }

    private func updateTitle(_ snapshot: UsageSnapshot?, showsProgress: Bool? = nil) {
        guard let button = statusItem.button else { return }
        button.toolTip = state.usageStatus.message
        let progress = showsProgress ?? state.showsProgressInMenuBar
        guard state.showsPercentagesInMenuBar || progress, let snapshot else {
            showIcon(in: button)
            return
        }

        let windows = [snapshot.primaryWindow, snapshot.secondaryWindow].compactMap { $0 }
        guard !windows.isEmpty else {
            showIcon(in: button)
            return
        }

        button.contentTintColor = nil
        button.image = nil
        button.imagePosition = .noImage
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        let title = MenuBarPresentation.title(
            windows: windows,
            showsPercentages: state.showsPercentagesInMenuBar,
            showsProgress: progress,
            textSize: state.menuBarTextSize
        )

        let updatedLabel = String(localized: "usage.updated")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedTime = snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)
        var attributes = updatedAtAttributes()
        if state.usageStatus.needsAttention {
            attributes[.foregroundColor] = NSColor.systemRed
        }
        let updatedTitle = NSAttributedString(
            string: state.usageStatus.message.map { "! \($0)" }
                ?? "\(updatedLabel) \(updatedTime)",
            attributes: attributes
        )
        percentagesLabel.alphaValue = state.usageStatus.needsAttention ? 0.5 : 1

        percentagesLabel.attributedStringValue = title
        updatedAtLabel.attributedStringValue = updatedTitle
        textStack.isHidden = false
        statusItem.length = ceil(max(title.size().width, updatedTitle.size().width) + 12)
    }

    private func showIcon(in button: NSButton) {
        textStack.isHidden = true
        statusItem.length = NSStatusItem.squareLength
        if state.usageStatus.needsAttention {
            button.image = NSImage(systemSymbolName: "exclamationmark.circle.fill",
                                   accessibilityDescription: state.usageStatus.message)
            button.contentTintColor = .systemRed
            button.imagePosition = .imageOnly
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            return
        }
        button.contentTintColor = nil
        let image = NSImage(named: "MenuBarIcon")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
    }

    private func updatedAtAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func refreshNow() {
        Task { await state.refresh() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// Shared with the settings preview so its spacing matches the status item.
enum MenuBarPresentation {
    @MainActor
    static func resetCreditsSection(
        resetCredits: UsageResetCredits?,
        usageStatus: UsageStatus,
        date: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> [NSMenuItem] {
        let item = NSMenuItem(title: String(localized: "Usage limit resets"), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "arrow.counterclockwise.circle", accessibilityDescription: item.title)
        item.isEnabled = false
        var items = [item]

        func addDetail(_ title: String, toolTip: String? = nil) {
            let detail = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            detail.isEnabled = false
            detail.toolTip = toolTip
            items.append(detail)
        }

        guard usageStatus != .signedOut else {
            addDetail(String(localized: "Sign in to fetch usage"))
            return items + [.separator()]
        }
        guard let resetCredits else {
            addDetail(String(localized: "Reset information is unavailable. Try refreshing."))
            return items + [.separator()]
        }

        let count = resetCredits.availableCount(at: date)
        item.title = String(
            format: String(localized: "Available resets: %@"),
            count.formatted(.number.locale(locale))
        )

        if usageStatus == .failed {
            addDetail(String(localized: "Refresh failed"))
        }

        let credits = resetCredits.availableCredits(at: date)
        for credit in credits {
            if let expiresAt = credit.expiresAt {
                addDetail(
                    ResetExpiration.shortText(for: expiresAt, locale: locale, timeZone: timeZone),
                    toolTip: ResetExpiration.text(for: expiresAt, locale: locale, timeZone: timeZone)
                )
            } else {
                addDetail(String(localized: "Expiration not provided"))
            }
        }
        if count > credits.count {
            addDetail(String(localized: "Some expiration dates are unavailable. Try refreshing."))
        }
        return items + [.separator()]
    }

    static func title(
        windows: [UsageWindow],
        showsPercentages: Bool,
        showsProgress: Bool,
        textSize: MenuBarTextSize
    ) -> NSAttributedString {
        let title = NSMutableAttributedString()
        guard showsPercentages || showsProgress else { return title }
        let font = NSFont.monospacedDigitSystemFont(ofSize: CGFloat(textSize.pointSize), weight: .semibold)
        for (index, window) in windows.enumerated() {
            if index > 0 {
                title.append(NSAttributedString(string: " / ", attributes: [
                    .font: font, .foregroundColor: NSColor.secondaryLabelColor
                ]))
            }
            let color = metricColor(window.remainingPercent)
            if showsProgress {
                let width: CGFloat = windows.count == 1 ? 32 : 16
                let attachment = NSTextAttachment()
                attachment.image = NSImage(size: NSSize(width: width, height: 5), flipped: false) { rect in
                    NSColor.labelColor.withAlphaComponent(0.18).setFill()
                    let track = NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5)
                    track.fill()
                    let fraction = CGFloat(window.remainingPercent / 100)
                    if fraction > 0 {
                        NSGraphicsContext.saveGraphicsState()
                        track.addClip()
                        color.setFill()
                        NSBezierPath(rect: NSRect(
                            x: rect.minX, y: rect.minY,
                            width: rect.width * fraction, height: rect.height
                        )).fill()
                        NSGraphicsContext.restoreGraphicsState()
                    }
                    return true
                }
                attachment.bounds = NSRect(x: 0, y: (font.capHeight - 5) / 2, width: width, height: 5)
                let meter = NSMutableAttributedString(attachment: attachment)
                meter.addAttribute(.font, value: font, range: NSRange(location: 0, length: meter.length))
                title.append(meter)
            }
            if showsPercentages {
                let prefix = showsProgress ? " " : ""
                title.append(NSAttributedString(
                    string: prefix + UsagePercentFormatter.format(window.remainingPercent),
                    attributes: [.font: font, .foregroundColor: color]
                ))
            }
        }
        return title
    }

    private static func metricColor(_ percent: Double) -> NSColor {
        let settings = UsageColorSettingsStore.current
        let level = UsageLevel.resolve(percent)
        return NSColor(name: nil) { appearance in
            let paletteAppearance: UsagePaletteAppearance =
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
            let value = settings.resolvedColor(for: level, appearance: paletteAppearance)
            return NSColor(calibratedHue: value.hue, saturation: value.saturation,
                           brightness: value.brightness, alpha: 1)
        }
    }
}
