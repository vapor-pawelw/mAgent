import Cocoa
import MagentCore

final class OnboardingPermissionsView: NSView {

    var permissionMode: AgentPermissionMode {
        if unrestrictedRadioButton.state == .on {
            return .unrestricted
        }
        if sandboxRadioButton.state == .on {
            return .sandboxAuto
        }
        return .askEveryTime
    }

    private let unrestrictedRadioButton = NSButton(
        radioButtonWithTitle: String(localized: .ConfigurationStrings.permissionsSkipPrompts),
        target: nil,
        action: nil
    )
    private let sandboxRadioButton = NSButton(
        radioButtonWithTitle: String(localized: .ConfigurationStrings.permissionsEnableSandbox),
        target: nil,
        action: nil
    )
    private let askEveryTimeRadioButton = NSButton(
        radioButtonWithTitle: String(localized: .ConfigurationStrings.permissionsAskEveryTime),
        target: nil,
        action: nil
    )
    private let permissionModeLabel = NSTextField(labelWithString: String(localized: .ConfigurationStrings.permissionsDescription))
    private let permissionModeExplanationLabel = NSTextField(
        wrappingLabelWithString: String(localized: .ConfigurationStrings.permissionsEnableSandboxDescriptionOnboarding)
    )
    private let unrestrictedDescription = String(localized: .ConfigurationStrings.permissionsSkipPromptsDescription)
    private let sandboxDescription = String(localized: .ConfigurationStrings.permissionsEnableSandboxDescriptionOnboarding)
    private let askEveryTimeDescription = String(localized: .ConfigurationStrings.permissionsAskEveryTimeDescription)

    private let fdaStatusLabel = NSTextField(labelWithString: "")
    private var appActiveObserver: NSObjectProtocol?

    override var isHidden: Bool {
        didSet {
            if !isHidden { refreshFDAStatus() }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        let titleLabel = NSTextField(labelWithString: String(localized: .ConfigurationStrings.permissionsTitle))
        titleLabel.font = .preferredFont(forTextStyle: .headline)

        permissionModeLabel.font = .systemFont(ofSize: 11)
        permissionModeLabel.textColor = NSColor(resource: .textSecondary)

        unrestrictedRadioButton.target = self
        unrestrictedRadioButton.action = #selector(permissionModeChanged)
        sandboxRadioButton.target = self
        sandboxRadioButton.action = #selector(permissionModeChanged)
        askEveryTimeRadioButton.target = self
        askEveryTimeRadioButton.action = #selector(permissionModeChanged)
        askEveryTimeRadioButton.state = .off
        unrestrictedRadioButton.state = .on
        sandboxRadioButton.state = .off

        permissionModeExplanationLabel.font = .systemFont(ofSize: 11)
        permissionModeExplanationLabel.textColor = NSColor(resource: .textSecondary)
        permissionModeExplanationLabel.maximumNumberOfLines = 0

        // FDA section
        let fdaLabel = NSTextField(labelWithString: String(localized: .ConfigurationStrings.permissionsFullDiskAccessTitle))
        fdaLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let fdaDesc = NSTextField(
            wrappingLabelWithString: String(localized: .ConfigurationStrings.permissionsFullDiskAccessDescriptionShort)
        )
        fdaDesc.font = .systemFont(ofSize: 11)
        fdaDesc.textColor = NSColor(resource: .textSecondary)

        let fdaStatusRow = NSStackView()
        fdaStatusRow.orientation = .horizontal
        fdaStatusRow.alignment = .centerY
        fdaStatusRow.spacing = 8

        fdaStatusLabel.font = .systemFont(ofSize: 12)
        fdaStatusRow.addArrangedSubview(fdaStatusLabel)

        let fdaButton = NSButton(title: String(localized: .CommonStrings.commonOpenSystemSettings), target: self, action: #selector(openFDASettings))
        fdaButton.bezelStyle = .push
        fdaButton.controlSize = .small
        fdaStatusRow.addArrangedSubview(fdaButton)

        let stack = NSStackView(views: [
            titleLabel, permissionModeLabel,
            unrestrictedRadioButton,
            sandboxRadioButton,
            askEveryTimeRadioButton,
            permissionModeExplanationLabel,
            fdaLabel, fdaDesc, fdaStatusRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.setCustomSpacing(16, after: permissionModeExplanationLabel)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        refreshFDAStatus()
        refreshPermissionModeDescription()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            appActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.isHidden else { return }
                    self.refreshFDAStatus()
                }
            }
        } else if let observer = appActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            appActiveObserver = nil
        }
    }

    private func refreshFDAStatus() {
        let granted = SystemAccessChecker.isFullDiskAccessGranted()
        if granted {
            fdaStatusLabel.stringValue = String(localized: .ConfigurationStrings.permissionsFullDiskAccessGranted)
            fdaStatusLabel.textColor = .systemGreen
        } else {
            fdaStatusLabel.stringValue = String(localized: .ConfigurationStrings.permissionsFullDiskAccessNotGranted)
            fdaStatusLabel.textColor = .secondaryLabelColor
        }
    }

    @objc private func openFDASettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func permissionModeChanged(_ sender: NSButton) {
        if sender === sandboxRadioButton {
            sandboxRadioButton.state = .on
            askEveryTimeRadioButton.state = .off
            unrestrictedRadioButton.state = .off
        } else if sender === unrestrictedRadioButton {
            sandboxRadioButton.state = .off
            askEveryTimeRadioButton.state = .off
            unrestrictedRadioButton.state = .on
        } else {
            sandboxRadioButton.state = .off
            askEveryTimeRadioButton.state = .on
            unrestrictedRadioButton.state = .off
        }
        refreshPermissionModeDescription()
    }

    private func refreshPermissionModeDescription() {
        switch permissionMode {
        case .sandboxAuto:
            permissionModeExplanationLabel.stringValue = sandboxDescription
        case .unrestricted:
            permissionModeExplanationLabel.stringValue = unrestrictedDescription
        case .askEveryTime:
            permissionModeExplanationLabel.stringValue = askEveryTimeDescription
        }
    }
}
