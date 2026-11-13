import AppKit

/// One place for every macOS permission BingZip needs. macOS cannot grant
/// TCC permissions programmatically, so this window explains and opens the
/// exact settings panes, while enabling the Finder extension automatically.
final class PermissionsDialog: NSWindowController, NSWindowDelegate {

    private var finderStatusLabel: NSTextField!
    private var fdaStatusLabel: NSTextField!
    private var enableFinderButton: NSButton!
    private var activationObserver: NSObjectProtocol?

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 310),
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        w.contentMinSize = NSSize(width: 600, height: 300)
        w.title = "权限设置 · \(AppInfo.name)"
        super.init(window: w)
        w.delegate = self
        FinderIntegration.register()
        buildContent()
        refreshStatus()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    // MARK: - Layout

    private func label(_ text: String, bold: Bool = false, size: CGFloat = 12) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = bold ? .systemFont(ofSize: size, weight: .semibold) : .systemFont(ofSize: size)
        l.lineBreakMode = .byTruncatingMiddle
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    private func wrappingLabel(_ text: String, size: CGFloat = 12) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: size)
        l.textColor = .secondaryLabelColor
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    private func spacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func buildContent() {
        guard let cv = window?.contentView else { return }

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "lock.shield.fill",
                             accessibilityDescription: "权限")
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let title = label("权限设置", bold: true, size: 20)
        let subtitle = label("一次完成,减少逐个文件夹授权", size: 12)
        subtitle.textColor = .secondaryLabelColor
        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 3
        let header = NSStackView(views: [icon, titleStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        let explanation = wrappingLabel("""
        macOS 不允许应用自动授予敏感权限。下面的两项只需设置一次;\
        开启完全磁盘访问后,扫描、压缩、解压不会再去逐个询问桌面、文稿、下载等文件夹。
        """)

        // Finder right-click extension
        let finderTitle = label("Finder 右键菜单", bold: true, size: 13)
        finderStatusLabel = label("")
        enableFinderButton = NSButton(title: "一键启用", target: self, action: #selector(enableFinder))
        enableFinderButton.bezelStyle = .rounded
        let finderSettingsButton = NSButton(title: "打开系统设置",
                                            target: self, action: #selector(openFinderSettings))
        finderSettingsButton.bezelStyle = .rounded
        let finderRow = NSStackView(views: [finderTitle, finderStatusLabel, spacer(),
                                            enableFinderButton, finderSettingsButton])
        finderRow.orientation = .horizontal
        finderRow.alignment = .centerY
        finderRow.spacing = 8

        // Full Disk Access
        let fdaTitle = label("完全磁盘访问", bold: true, size: 13)
        fdaStatusLabel = label("")
        let fdaSettingsButton = NSButton(title: "打开完全磁盘访问设置",
                                         target: self, action: #selector(openFDASettings))
        fdaSettingsButton.bezelStyle = .rounded
        let revealButton = NSButton(title: "在 Finder 中显示 BingZip",
                                    target: self, action: #selector(revealApp))
        revealButton.bezelStyle = .rounded
        let fdaRow = NSStackView(views: [fdaTitle, fdaStatusLabel, spacer(),
                                         fdaSettingsButton, revealButton])
        fdaRow.orientation = .horizontal
        fdaRow.alignment = .centerY
        fdaRow.spacing = 8

        let hint = wrappingLabel("""
        完全磁盘访问会同时覆盖桌面、文稿、下载、外接磁盘和网络卷。\
        打开设置后把 BingZip.app 加入列表并打开开关;如果列表中没有,可点\
        “在 Finder 中显示 BingZip”后拖入,或点列表下方的 + 选择应用。\
        授权完成后请退出并重新打开 BingZip。
        """)

        let recheckButton = NSButton(title: "重新检查", target: self, action: #selector(recheck))
        recheckButton.bezelStyle = .rounded
        let openAllButton = NSButton(title: "打开所需设置", target: self, action: #selector(openAllSettings))
        openAllButton.bezelStyle = .rounded
        let doneButton = NSButton(title: "完成", target: self, action: #selector(closeWindow))
        doneButton.keyEquivalent = "\r"
        doneButton.bezelStyle = .rounded
        let footer = NSStackView(views: [recheckButton, spacer(), openAllButton, doneButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8

        let root = NSStackView(views: [header, explanation, separator(), finderRow,
                                       fdaRow, separator(), hint, footer])
        root.orientation = .vertical
        root.alignment = .leading
        root.distribution = .fill
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(root)

        let separators = root.arrangedSubviews.compactMap { $0 as? NSBox }
            .filter { $0.boxType == .separator }
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: cv.topAnchor, constant: 16),
            root.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            root.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -12),
            explanation.widthAnchor.constraint(equalTo: root.widthAnchor),
            finderRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            fdaRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            hint.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor),
        ] + separators.map { $0.widthAnchor.constraint(equalTo: root.widthAnchor) })
    }

    // MARK: - Status

    private func refreshStatus() {
        guard finderStatusLabel != nil else { return }

        let finderEnabled = FinderIntegration.isEnabled
        let fda = SystemPermissions.fullDiskAccessState

        finderStatusLabel.stringValue = finderEnabled ? "已启用" : "未启用"
        finderStatusLabel.textColor = finderEnabled ? .systemGreen : .systemOrange
        enableFinderButton.isEnabled = !finderEnabled

        fdaStatusLabel.stringValue = fda.title
        switch fda {
        case .granted: fdaStatusLabel.textColor = .systemGreen
        case .denied: fdaStatusLabel.textColor = .systemOrange
        case .unknown: fdaStatusLabel.textColor = .secondaryLabelColor
        }
    }

    // MARK: - Actions

    @objc func enableFinder() {
        if FinderIntegration.enable() {
            AppLogger.shared.log("Permissions: Finder extension enabled")
        } else {
            AppLogger.shared.log("Permissions: Finder extension enable failed")
            FinderIntegration.openSettings()
        }
        refreshStatus()
    }

    @objc func openFinderSettings() {
        FinderIntegration.openSettings()
    }

    @objc func openFDASettings() {
        SystemPermissions.openFullDiskAccessSettings()
    }

    @objc func revealApp() {
        SystemPermissions.revealAppInFinder()
    }

    @objc func openAllSettings() {
        if !FinderIntegration.isEnabled {
            _ = FinderIntegration.enable()
        }
        if SystemPermissions.fullDiskAccessState != .granted {
            SystemPermissions.openFullDiskAccessSettings()
        }
        refreshStatus()
    }

    @objc func recheck() {
        refreshStatus()
    }

    @objc func closeWindow() {
        window?.orderOut(nil)
        NSApp.stopModal()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeWindow()
        return true
    }

    func runModal(on parent: NSWindow?) {
        guard let w = window else { return }
        w.center()
        NSApp.runModal(for: w)
    }
}
