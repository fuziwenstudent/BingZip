import AppKit

/// BingZip settings dialog: general options, engine/RAR status, log tools and
/// bookmark management.
final class SettingsDialog: NSWindowController, NSWindowDelegate {

    private var showHiddenButton: NSButton!
    private var rarStatusLabel: NSTextField!
    private var rarPathLabel: NSTextField!
    private var logSummaryLabel: NSTextField!
    private var finderStatusLabel: NSTextField!
    private var finderStartupButton: NSButton!

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 450),
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        w.contentMinSize = NSSize(width: 480, height: 450)
        w.title = "设置"
        super.init(window: w)
        w.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func label(_ text: String, size: CGFloat = 12,
                       weight: NSFont.Weight = .regular) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        return l
    }

    private func buildContent() {
        guard let cv = window?.contentView else { return }

        let defaults = UserDefaults.standard

        // General settings
        showHiddenButton = NSButton(checkboxWithTitle: "显示隐藏文件",
                                    target: self, action: #selector(toggleHidden))
        showHiddenButton.state = defaults.bool(forKey: "BingZipShowHidden") ? .on : .off

        // Engine status (self-test)
        var engineStatus = "不可用"
        var versionLine = "7-Zip (7zz)"
        let engineURL = SevenZip.shared.binaryURL
        if FileManager.default.isExecutableFile(atPath: engineURL.path),
           let r = try? SevenZip.shared.run(["i"]), r.exitCode == 0 {
            engineStatus = "可用 ✓"
            if let line = (r.stdout + "\n" + r.stderr)
                .split(separator: "\n")
                .first(where: { $0.contains("7-Zip") }) {
                versionLine = String(line).trimmingCharacters(in: .whitespaces)
            }
        }
        let engineLabel = label("压缩引擎: \(versionLine)")
        let statusLabel = label("状态: \(engineStatus)", weight: .medium)
        statusLabel.textColor = engineStatus.hasPrefix("可用") ? .systemGreen : .systemRed
        let pathLabel = label("引擎位置: " + engineURL.path, size: 10)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // RAR creation tool
        let rarTitle = label("RAR 压缩工具", weight: .semibold)
        rarStatusLabel = label("")
        rarPathLabel = label("", size: 10)
        rarPathLabel.textColor = .secondaryLabelColor
        rarPathLabel.lineBreakMode = .byTruncatingMiddle
        rarPathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let rarInfo = NSStackView(views: [rarStatusLabel, rarPathLabel])
        rarInfo.orientation = .horizontal
        rarInfo.spacing = 8
        rarInfo.alignment = .firstBaseline
        let chooseRar = NSButton(title: "选择 rar…", target: self, action: #selector(chooseRarTool))
        chooseRar.bezelStyle = .rounded
        let downloadRar = NSButton(title: "下载 RAR…", target: self, action: #selector(downloadRarTool))
        downloadRar.bezelStyle = .rounded
        let detectRar = NSButton(title: "重新检测", target: self, action: #selector(redetectRarTool))
        detectRar.bezelStyle = .rounded
        let rarButtons = NSStackView(views: [chooseRar, downloadRar, detectRar])
        rarButtons.orientation = .horizontal
        rarButtons.spacing = 8

        // Log tools
        let logTitle = label("日志", weight: .semibold)
        logSummaryLabel = label("")
        logSummaryLabel.textColor = .secondaryLabelColor
        logSummaryLabel.lineBreakMode = .byTruncatingTail
        logSummaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let logInfo = NSStackView(views: [logTitle, logSummaryLabel])
        logInfo.orientation = .horizontal
        logInfo.spacing = 8
        let exportLogs = NSButton(title: "导出日志…", target: self, action: #selector(exportLogs))
        exportLogs.bezelStyle = .rounded
        let clearLogs = NSButton(title: "完全清除日志…", target: self, action: #selector(clearLogs))
        clearLogs.bezelStyle = .rounded
        let openLogs = NSButton(title: "打开日志文件夹", target: self, action: #selector(openLogs))
        openLogs.bezelStyle = .rounded
        let logButtons = NSStackView(views: [exportLogs, clearLogs, openLogs])
        logButtons.orientation = .horizontal
        logButtons.spacing = 8

        // Permissions (Finder extension + Full Disk Access)
        let finderTitle = label("权限", weight: .semibold)
        finderStatusLabel = label("")
        finderStatusLabel.textColor = .secondaryLabelColor
        finderStatusLabel.lineBreakMode = .byTruncatingTail
        finderStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        finderStartupButton = NSButton(checkboxWithTitle: "启动时检查权限",
                                       target: self, action: #selector(toggleFinderStartupCheck))
        finderStartupButton.state = SystemPermissions.isStartupCheckEnabled ? .on : .off
        let checkFinder = NSButton(title: "权限设置…", target: self, action: #selector(checkFinderMenu))
        checkFinder.bezelStyle = .rounded
        let finderButtons = NSStackView(views: [finderStartupButton, checkFinder])
        finderButtons.orientation = .horizontal
        finderButtons.spacing = 10
        let finderInfo = NSStackView(views: [finderStatusLabel])
        finderInfo.orientation = .horizontal
        finderInfo.spacing = 8

        // Bookmarks
        let bookmarks = defaults.stringArray(forKey: "BingZipBookmarks") ?? []
        let bookmarkLabel = label("收藏夹 (\(bookmarks.count) 项)")
        let clearBookmarks = NSButton(title: "清空收藏夹", target: self, action: #selector(clearBookmarks))
        clearBookmarks.bezelStyle = .rounded

        let bookmarkRow = NSStackView(views: [bookmarkLabel, clearBookmarks])
        bookmarkRow.orientation = .horizontal
        bookmarkRow.spacing = 10

        let ok = NSButton(title: "确定", target: self, action: #selector(closeWindow))
        ok.keyEquivalent = "\r"
        ok.bezelStyle = .rounded


        let separator1 = NSBox.separatorLine()
        let separator2 = NSBox.separatorLine()
        let separator3 = NSBox.separatorLine()
        let separator4 = NSBox.separatorLine()
        let separator5 = NSBox.separatorLine()

        let sv = NSStackView()
        sv.orientation = .vertical
        sv.alignment = .leading
        sv.spacing = 10
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.addArrangedSubview(showHiddenButton)
        sv.addArrangedSubview(separator1)
        sv.addArrangedSubview(engineLabel)
        sv.addArrangedSubview(statusLabel)
        sv.addArrangedSubview(pathLabel)
        sv.addArrangedSubview(separator2)
        sv.addArrangedSubview(rarTitle)
        sv.addArrangedSubview(rarInfo)
        sv.addArrangedSubview(rarButtons)
        sv.addArrangedSubview(separator3)
        sv.addArrangedSubview(logInfo)
        sv.addArrangedSubview(logButtons)
        sv.addArrangedSubview(separator4)
        sv.addArrangedSubview(finderTitle)
        sv.addArrangedSubview(finderInfo)
        sv.addArrangedSubview(finderButtons)
        sv.addArrangedSubview(separator5)
        sv.addArrangedSubview(bookmarkRow)
        sv.addArrangedSubview(ok)
        cv.addSubview(sv)
        let separators = [separator1, separator2, separator3, separator4, separator5]
        NSLayoutConstraint.activate([
            sv.topAnchor.constraint(equalTo: cv.topAnchor, constant: 16),
            sv.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            sv.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            sv.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor, constant: -12),
            rarInfo.widthAnchor.constraint(lessThanOrEqualTo: cv.widthAnchor, constant: -32),
            logInfo.widthAnchor.constraint(lessThanOrEqualTo: cv.widthAnchor, constant: -32),
            finderInfo.widthAnchor.constraint(lessThanOrEqualTo: cv.widthAnchor, constant: -32),
        ] + separators.map { $0.widthAnchor.constraint(equalTo: sv.widthAnchor) })

        refreshRarStatus()
        refreshLogSummary()
        refreshFinderStatus()
    }

    // MARK: - Status

    private func refreshRarStatus() {
        RarTool.shared.reload()
        if RarTool.shared.isAvailable, let url = RarTool.shared.binaryURL {
            rarStatusLabel.stringValue = "RAR 创建:可用 ✓"
            rarStatusLabel.textColor = .systemGreen
            rarPathLabel.stringValue = url.path
        } else {
            rarStatusLabel.stringValue = "RAR 创建:未安装(仍可解压 RAR)"
            rarStatusLabel.textColor = .secondaryLabelColor
            rarPathLabel.stringValue = "创建 RAR 需 RARLAB 的 rar 工具;可点“选择 rar…”指定"
        }
    }

    private func refreshLogSummary() {
        let files = AppLogger.shared.logFiles()
        let crash = files.filter { $0.isCrash }.count
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        logSummaryLabel.stringValue = files.isEmpty
            ? "暂无日志"
            : "\(files.count) 个文件 · 崩溃日志 \(crash) 个 · \(formatBytes(total))"
    }

    private func refreshFinderStatus() {
        let finderEnabled = FinderIntegration.isEnabled
        let fda = SystemPermissions.fullDiskAccessState

        if !FinderIntegration.isBundled {
            finderStatusLabel.stringValue = "右键菜单未捆绑 · 完全磁盘访问\(fda.title)"
            finderStatusLabel.textColor = .secondaryLabelColor
        } else {
            let finderText = finderEnabled ? "右键菜单已启用" : "右键菜单未启用"
            finderStatusLabel.stringValue = "\(finderText) · 完全磁盘访问\(fda.title)"
            if finderEnabled && fda == .granted {
                finderStatusLabel.textColor = .systemGreen
            } else if finderEnabled && fda == .unknown {
                finderStatusLabel.textColor = .secondaryLabelColor
            } else {
                finderStatusLabel.textColor = .systemOrange
            }
        }
        finderStartupButton.state = SystemPermissions.isStartupCheckEnabled ? .on : .off
    }

    // MARK: - Actions

    @objc func toggleHidden() {
        UserDefaults.standard.set(showHiddenButton.state == .on, forKey: "BingZipShowHidden")
    }

    @objc func chooseRarTool() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "选择 RARLAB 的 rar 命令行工具"
        if FileManager.default.fileExists(atPath: "/usr/local/bin") {
            panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if RarTool.shared.setCustomBinary(url) {
            refreshRarStatus()
        } else {
            let a = NSAlert()
            a.messageText = "无法使用这个文件"
            a.informativeText = "请选择可执行的 rar 命令行工具(不是图形界面 App)。"
            a.addButton(withTitle: "好")
            a.runModal()
        }
    }

    @objc func downloadRarTool() {
        NSWorkspace.shared.open(AppInfo.rarDownloadPage)
    }

    @objc func redetectRarTool() {
        RarTool.shared.reload()
        refreshRarStatus()
    }

    @objc func exportLogs() {
        LogActions.export(from: window)
        refreshLogSummary()
    }

    @objc func clearLogs() {
        if LogActions.clearAll(from: window) {
            refreshLogSummary()
        }
    }

    @objc func openLogs() {
        NSWorkspace.shared.open(AppLogger.shared.logDirectory)
    }

    @objc func toggleFinderStartupCheck() {
        SystemPermissions.isStartupCheckEnabled = finderStartupButton.state == .on
    }

    @objc func checkFinderMenu() {
        PermissionsDialog().runModal(on: window)
        refreshFinderStatus()
    }

    @objc func clearBookmarks() {
        UserDefaults.standard.set([String](), forKey: "BingZipBookmarks")
        if let delegate = NSApp.delegate as? AppDelegate {
            NSApp.mainMenu = delegate.buildMenu()
        }
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

private extension NSBox {
    static func separatorLine() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}

