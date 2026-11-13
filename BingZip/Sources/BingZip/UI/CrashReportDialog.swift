import AppKit

/// Shown automatically at the next launch when the previous session crashed.
/// Explains what happened and displays the saved crash log.
final class CrashReportDialog: NSWindowController, NSWindowDelegate {

    private let report: AppLogger.LogFileInfo
    private let content: String
    private var completion: (() -> Void)?
    private var didComplete = false

    init(report: AppLogger.LogFileInfo) {
        self.report = report
        self.content = (try? String(contentsOf: report.url, encoding: .utf8))
            ?? "无法读取崩溃日志文件:\(report.url.path)"
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 640),
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        w.contentMinSize = NSSize(width: 620, height: 480)
        w.title = "上次运行崩溃报告 · \(AppInfo.name)"
        super.init(window: w)
        w.delegate = self
        buildContent()
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

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                             accessibilityDescription: "崩溃")
        icon.contentTintColor = .systemOrange
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let title = label("BingZip 上次运行时崩溃了", bold: true, size: 20)
        let subtitle = label("崩溃日志已自动保存,下面是本次崩溃的详细信息。", size: 12)
        subtitle.textColor = .secondaryLabelColor
        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 3
        let header = NSStackView(views: [icon, titleStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        let explanation = NSTextField(wrappingLabelWithString: """
        BingZip 检测到上次运行没有正常退出,已捕获未处理的异常或致命信号。\
        你可以复制下面的日志、导出全部日志,或打开日志文件夹,把信息反馈给开发者以便定位问题。
        """)
        explanation.font = .systemFont(ofSize: 12)
        explanation.textColor = .secondaryLabelColor
        explanation.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timeText = report.modified.map { df.string(from: $0) } ?? "未知"

        let info = NSGridView(views: [])
        info.rowSpacing = 6
        info.columnSpacing = 12
        info.addRow(with: [label("崩溃类型", bold: true), label(crashKind)])
        let fileLabel = label(report.url.lastPathComponent)
        fileLabel.lineBreakMode = .byTruncatingMiddle
        info.addRow(with: [label("日志文件", bold: true), fileLabel])
        info.addRow(with: [label("发生时间", bold: true), label(timeText)])
        info.addRow(with: [label("应用版本", bold: true),
                           label("\(AppInfo.name) \(AppInfo.version) (\(AppInfo.build))")])
        info.column(at: 0).xPlacement = .trailing

        let infoRow = NSStackView(views: [info, spacer()])
        infoRow.orientation = .horizontal
        infoRow.alignment = .top
        infoRow.spacing = 0

        let logTextView = NSTextView()
        logTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.string = content
        let logScroll = makeScrollView(logTextView)
        logScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        logScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        logScroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let copyButton = NSButton(title: "复制日志", target: self, action: #selector(copyLog))
        copyButton.bezelStyle = .rounded
        let exportButton = NSButton(title: "导出日志…", target: self, action: #selector(exportLogs))
        exportButton.bezelStyle = .rounded
        let folderButton = NSButton(title: "打开日志文件夹", target: self, action: #selector(openLogFolder))
        folderButton.bezelStyle = .rounded
        let closeButton = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
        closeButton.keyEquivalent = "\r"
        closeButton.bezelStyle = .rounded
        let buttonRow = NSStackView(views: [copyButton, exportButton, folderButton, spacer(), closeButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let root = NSStackView(views: [header, explanation, infoRow, logScroll, buttonRow])
        root.orientation = .vertical
        root.alignment = .leading
        root.distribution = .fill
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: cv.topAnchor, constant: 16),
            root.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            root.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -12),
            explanation.widthAnchor.constraint(equalTo: root.widthAnchor),
            infoRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            logScroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
    }

    /// A short, human readable crash type parsed from the log.
    private var crashKind: String {
        let lines = content.split(separator: "\n").map(String.init)
        if let signalLine = lines.first(where: { $0.lowercased().contains("fatal signal") }) {
            if let number = Int32(signalLine.filter { $0.isNumber }) {
                return "\(Self.signalName(number)) (\(number))"
            }
            return signalLine
        }
        if let exception = lines.first(where: { $0.hasPrefix("Exception:") }) {
            if let reason = lines.first(where: { $0.hasPrefix("Reason:") }) {
                let text = reason.replacingOccurrences(of: "Reason:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return "\(exception) · \(text)"
            }
            return exception
        }
        return "未知(详见日志)"
    }

    private static func signalName(_ sig: Int32) -> String {
        switch sig {
        case SIGSEGV: return "段错误 SIGSEGV"
        case SIGABRT: return "异常中止 SIGABRT"
        case SIGBUS: return "总线错误 SIGBUS"
        case SIGILL: return "非法指令 SIGILL"
        case SIGFPE: return "算术异常 SIGFPE"
        case SIGTRAP: return "陷阱 SIGTRAP"
        default: return "致命信号"
        }
    }

    // MARK: - Actions

    @objc func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    @objc func exportLogs() {
        LogActions.export(from: window)
    }

    @objc func openLogFolder() {
        NSWorkspace.shared.open(AppLogger.shared.logDirectory)
    }

    @objc func closeWindow() {
        guard !didComplete else { return }
        didComplete = true
        let done = completion
        completion = nil
        window?.orderOut(nil)
        NSApp.stopModal()
        done?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeWindow()
        return true
    }

    func runModal(on parent: NSWindow?, completion: @escaping () -> Void) {
        self.completion = completion
        guard let w = window else {
            completion()
            return
        }
        w.center()
        NSApp.runModal(for: w)
    }
}

/// Detects crash logs written since the previous launch and presents the newest
/// one automatically. Runs once per launch.
enum CrashReportPresenter {

    private static let lastLaunchKey = "BingZipLastLaunchDate"

    static func presentIfNeeded(on parent: NSWindow?) {
        let defaults = UserDefaults.standard
        let now = Date()
        let previous = (defaults.object(forKey: lastLaunchKey) as? Double)
            .map(Date.init(timeIntervalSince1970:))

        // Mark this launch before presenting, so the same report is shown once.
        defaults.set(now.timeIntervalSince1970, forKey: lastLaunchKey)

        guard let previousDate = previous else { return }
        let crashes = AppLogger.shared.logFiles().filter { $0.isCrash }
        guard let latest = crashes.first(where: { ($0.modified ?? .distantPast) > previousDate }) else {
            return
        }

        AppLogger.shared.log("Crash report: presenting \(latest.url.lastPathComponent)")
        let dialog = CrashReportDialog(report: latest)
        dialog.runModal(on: parent) {}
    }
}
