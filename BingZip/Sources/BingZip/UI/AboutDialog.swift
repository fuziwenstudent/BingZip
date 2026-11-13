import AppKit

/// Version / About dialog: app metadata, personal website, code page,
/// Finder extension status and crash-log management (export / clear).
final class AboutDialog: NSWindowController, NSWindowDelegate {

    private var logSummaryLabel: NSTextField!
    private var logTextView: NSTextView!
    private var rarLabel: NSTextField!
    private var finderLabel: NSTextField!
    private var codePagePopup: NSPopUpButton!

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 470),
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        w.contentMinSize = NSSize(width: 600, height: 420)
        w.title = "版本信息 · \(AppInfo.name)"
        super.init(window: w)
        w.delegate = self
        buildContent()
        refreshLogs()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Content

    private func label(_ text: String, bold: Bool = false, size: CGFloat = 12) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = bold ? .systemFont(ofSize: size, weight: .semibold) : .systemFont(ofSize: size)
        l.lineBreakMode = .byTruncatingMiddle
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

    private func websiteButton() -> NSButton {
        let b = NSButton(title: AppInfo.websiteDisplay, target: self, action: #selector(openWebsite))
        b.isBordered = false
        b.bezelStyle = .inline
        b.attributedTitle = NSAttributedString(
            string: AppInfo.websiteDisplay,
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: NSFont.systemFont(ofSize: 12),
            ])
        b.toolTip = "在默认浏览器中打开 \(AppInfo.websiteDisplay)"
        return b
    }

    // MARK: - Layout

    private func makeScrollView(_ textView: NSTextView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        return scroll
    }

    private func buildContent() {
        guard let cv = window?.contentView else { return }

        let title = label("\(AppInfo.name) \(AppInfo.version)", bold: true, size: 26)
        let subtitle = label("macOS 原生压缩软件 · \(AppInfo.engineDescription)")
        subtitle.textColor = .secondaryLabelColor
        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4

        let info = NSGridView(views: [])
        info.rowSpacing = 6
        info.columnSpacing = 10
        info.addRow(with: [label("版本", bold: true), label(AppInfo.version)])
        info.addRow(with: [label("压缩引擎", bold: true), label(AppInfo.engineDescription)])
        info.addRow(with: [label("个人网站", bold: true), websiteButton()])
        codePagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        codePagePopup.addItems(withTitles: CodePage.options.map { $0.title })
        codePagePopup.selectItem(at: CodePage.currentIndex)
        codePagePopup.target = self
        codePagePopup.action = #selector(codePageChanged)
        codePagePopup.translatesAutoresizingMaskIntoConstraints = false
        codePagePopup.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let codePageHint = label("创建 Zip 时用于文件名编码", size: 10)
        codePageHint.textColor = .secondaryLabelColor
        let codePageCell = NSStackView(views: [codePagePopup, codePageHint])
        codePageCell.orientation = .horizontal
        codePageCell.alignment = .centerY
        codePageCell.spacing = 6
        info.addRow(with: [label("代码页", bold: true), codePageCell])
        finderLabel = label("")
        finderLabel.lineBreakMode = .byTruncatingTail
        finderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let finderCheck = NSButton(title: "权限设置…", target: self, action: #selector(checkFinderMenu))
        finderCheck.bezelStyle = .rounded
        let finderCell = NSStackView(views: [finderLabel, finderCheck])
        finderCell.orientation = .horizontal
        finderCell.alignment = .centerY
        finderCell.spacing = 6
        info.addRow(with: [label("权限", bold: true), finderCell])
        rarLabel = label("")
        info.addRow(with: [label("RAR 压缩", bold: true), rarLabel])
        info.column(at: 0).xPlacement = .trailing

        // Keep the grid pinned to the left instead of being stretched inward.
        let infoRow = NSStackView(views: [info, spacer()])
        infoRow.orientation = .horizontal
        infoRow.alignment = .top
        infoRow.spacing = 0

        let logTitle = label("崩溃日志与运行日志", bold: true)
        logSummaryLabel = label("")
        logSummaryLabel.textColor = .secondaryLabelColor
        logSummaryLabel.lineBreakMode = .byTruncatingTail
        logSummaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let exportButton = NSButton(title: "导出…", target: self, action: #selector(exportLogs))
        exportButton.bezelStyle = .rounded
        let clearButton = NSButton(title: "完全清除…", target: self, action: #selector(clearLogs))
        clearButton.bezelStyle = .rounded
        let openButton = NSButton(title: "打开文件夹", target: self, action: #selector(openLogFolder))
        openButton.bezelStyle = .rounded
        let logButtons = NSStackView(views: [exportButton, clearButton, openButton])
        logButtons.orientation = .horizontal
        logButtons.spacing = 6
        let logHeader = NSStackView(views: [logTitle, logSummaryLabel, spacer(), logButtons])
        logHeader.orientation = .horizontal
        logHeader.alignment = .centerY
        logHeader.spacing = 8

        logTextView = NSTextView()
        logTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let logScroll = makeScrollView(logTextView)
        logScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
        logScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        logScroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let ok = NSButton(title: "确定", target: self, action: #selector(closeWindow))
        ok.keyEquivalent = "\r"
        ok.bezelStyle = .rounded
        let okRow = NSStackView(views: [spacer(), ok])
        okRow.orientation = .horizontal
        okRow.spacing = 8

        let root = NSStackView(views: [header, infoRow, separator(), logHeader,
                                       logScroll, separator(), okRow])
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

            logHeader.widthAnchor.constraint(equalTo: root.widthAnchor),
            infoRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            logScroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            okRow.widthAnchor.constraint(equalTo: root.widthAnchor),
        ] + separators.map { $0.widthAnchor.constraint(equalTo: root.widthAnchor) })
    }


    // MARK: - Logs

    private func refreshLogs() {
        let files = AppLogger.shared.logFiles()
        let crashCount = files.filter { $0.isCrash }.count
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        if files.isEmpty {
            logSummaryLabel.stringValue = "暂无日志"
            logTextView.string = "暂无日志文件。\n崩溃日志会自动保存在:\n\(AppLogger.shared.logDirectory.path)"
        } else {
            logSummaryLabel.stringValue = "共 \(files.count) 个文件 · 崩溃日志 \(crashCount) 个 · \(formatBytes(total))"
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            var lines = ["文件名\t大小\t修改时间"]
            for f in files {
                let date = f.modified.map { df.string(from: $0) } ?? "—"
                lines.append("\(f.url.lastPathComponent)\t\(formatBytes(f.size))\t\(date)")
            }
            logTextView.string = lines.joined(separator: "\n")
        }
        updateRarStatus()
        updateFinderStatus()
    }

    private func updateFinderStatus() {
        guard finderLabel != nil else { return }
        let finderEnabled = FinderIntegration.isEnabled
        let fda = SystemPermissions.fullDiskAccessState

        if !FinderIntegration.isBundled {
            finderLabel.stringValue = "右键菜单未捆绑 · 完全磁盘访问\(fda.title)"
            finderLabel.textColor = .secondaryLabelColor
            return
        }

        let finderText = finderEnabled ? "右键菜单已启用" : "右键菜单未启用"
        finderLabel.stringValue = "\(finderText) · 完全磁盘访问\(fda.title)"
        if finderEnabled && fda == .granted {
            finderLabel.textColor = .systemGreen
        } else if finderEnabled && fda == .unknown {
            finderLabel.textColor = .secondaryLabelColor
        } else {
            finderLabel.textColor = .systemOrange
        }
    }

    private func updateRarStatus() {
        RarTool.shared.reload()
        if RarTool.shared.isAvailable, let url = RarTool.shared.binaryURL {
            rarLabel.stringValue = "可用"
            rarLabel.textColor = .systemGreen
            rarLabel.toolTip = url.path
        } else {
            rarLabel.stringValue = "未安装 · 仅支持解压"
            rarLabel.textColor = .secondaryLabelColor
            rarLabel.toolTip = "RAR 创建需要 RARLAB 的 rar 工具;可在设置中选择。"
        }
    }

    // MARK: - Actions

    @objc func openWebsite() {
        NSWorkspace.shared.open(AppInfo.websiteURL)
    }

    @objc func checkFinderMenu() {
        PermissionsDialog().runModal(on: window)
        updateFinderStatus()
    }

    @objc func codePageChanged() {
        let index = max(0, min(codePagePopup.indexOfSelectedItem, CodePage.options.count - 1))
        let option = CodePage.options[index]
        CodePage.set(value: option.value)
        AppLogger.shared.log("Code page set to \(option.title)")
    }

    @objc func exportLogs() {
        LogActions.export(from: window)
    }

    @objc func clearLogs() {
        if LogActions.clearAll(from: window) {
            refreshLogs()
        }
    }

    @objc func openLogFolder() {
        NSWorkspace.shared.open(AppLogger.shared.logDirectory)
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
