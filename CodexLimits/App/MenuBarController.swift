import AppKit
import Combine

private final class MenuBarTextStackView: NSStackView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

@MainActor
final class MenuBarController: NSObject {
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
        menu.addItem(makeItem(
            String(localized: "menu.openSettings"),
            action: #selector(openSettings)
        ))
        menu.addItem(makeItem(
            String(localized: "content.refreshNow"),
            action: #selector(refreshNow)
        ))
        menu.addItem(.separator())
        menu.addItem(makeItem(
            String(localized: "menu.quit"),
            action: #selector(quit)
        ))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func makeItem(_ title: String, action: Selector) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: "")
    }

    private func updateTitle(_ snapshot: UsageSnapshot?) {
        guard let button = statusItem.button else { return }
        guard state.showsPercentagesInMenuBar, let snapshot else {
            showIcon(in: button)
            return
        }

        button.image = nil
        button.imagePosition = .noImage
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        let title = NSMutableAttributedString()
        appendPercent(snapshot.primaryWindow?.remainingPercent, to: title)
        title.append(NSAttributedString(
            string: " / ",
            attributes: baseAttributes(color: .secondaryLabelColor)
        ))
        appendPercent(snapshot.secondaryWindow?.remainingPercent, to: title)

        let updatedLabel = String(localized: "usage.updated")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedTime = snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)
        let updatedTitle = NSAttributedString(
            string: "\(updatedLabel) \(updatedTime)",
            attributes: updatedAtAttributes()
        )

        percentagesLabel.attributedStringValue = title
        updatedAtLabel.attributedStringValue = updatedTitle
        textStack.isHidden = false
        statusItem.length = ceil(max(title.size().width, updatedTitle.size().width) + 12)
    }

    private func showIcon(in button: NSButton) {
        textStack.isHidden = true
        statusItem.length = NSStatusItem.squareLength
        let image = NSImage(named: "MenuBarIcon")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
    }

    private func appendPercent(_ percent: Double?, to title: NSMutableAttributedString) {
        let color: NSColor
        if let percent {
            switch UsageLevel.resolve(percent) {
            case .normal: color = .systemGreen
            case .warning: color = .systemOrange
            case .danger: color = .systemRed
            }
        } else {
            color = .secondaryLabelColor
        }
        title.append(NSAttributedString(
            string: UsagePercentFormatter.format(percent),
            attributes: baseAttributes(color: color)
        ))
    }

    private func baseAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: CGFloat(state.menuBarTextSize.pointSize),
                weight: .semibold
            ),
            .foregroundColor: color
        ]
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
