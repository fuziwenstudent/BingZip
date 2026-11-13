import AppKit

/// 7-Zip style "Extract" dialog.
final class ExtractDialog: NSWindowController, NSWindowDelegate {

    private let archive: URL
    private let files: [String]?
    private var completion: (() -> Void)?

    private var destField: NSTextField!
    private var pathModePopup: NSPopUpButton!
    private var overwritePopup: NSPopUpButton!
    private var passwordField: NSSecureTextField!
    private var paramsField: NSTextField!
    private var flatModeButton: NSButton!
    private var includeField: NSTextField!
    private var excludeField: NSTextField!

    init(archive: URL, files: [String]?, suggestDirectory: URL) {
        self.archive = archive
        self.files = files
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 400),
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        w.contentMinSize = NSSize(width: 520, height: 380)
        w.title = "解压"
        super.init(window: w)
        w.delegate = self
        setup(suggest: suggestDirectory)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12)
        return l
    }

    private func setup(suggest: URL) {
        guard let cv = window?.contentView else { return }

        destField = NSTextField()
        destField.stringValue = suggest.appendingPathComponent(archive.deletingPathExtension().lastPathComponent).path
        destField.font = .systemFont(ofSize: 12)

        pathModePopup = NSPopUpButton()
        pathModePopup.addItems(withTitles: ["完整路径名称", "无路径(仅文件名)", "从路径中移除前缀", "按文件名附加路径"])
        overwritePopup = NSPopUpButton()
        overwritePopup.addItems(withTitles: ["覆盖所有文件", "跳过已有文件", "自动重命名解压的文件", "自动重命名已有文件"])

        passwordField = NSSecureTextField()
        passwordField.placeholderString = "(加密压缩包的密码,可选)"
        passwordField.font = .systemFont(ofSize: 12)

        paramsField = NSTextField()
        paramsField.placeholderString = "例如: -mcb.y2"
        paramsField.font = .systemFont(ofSize: 12)
        flatModeButton = NSButton(checkboxWithTitle: "仅解压文件(不含目录结构)", target: nil, action: nil)
        includeField = NSTextField()
        includeField.placeholderString = "包含: *.txt; *.jpg(分号分隔)"
        excludeField = NSTextField()
        excludeField.placeholderString = "排除: *.tmp; .DS_Store"

        let browse = NSButton(title: "浏览…", target: self, action: #selector(browseDest))
        browse.bezelStyle = .rounded
        let ok = NSButton(title: "确定", target: self, action: #selector(okClick))
        ok.keyEquivalent = "\r"
        ok.bezelStyle = .rounded
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelClick))
        cancel.keyEquivalent = "\u{1b}"
        cancel.bezelStyle = .rounded

        let grid = NSGridView(views: [])
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.addRow(with: [label("解压到:"), destField, browse])
        grid.addRow(with: [label("路径模式:"), pathModePopup])
        grid.addRow(with: [label("覆盖模式:"), overwritePopup])
        grid.addRow(with: [label("密码:"), passwordField])
        grid.addRow(with: [label("包含:"), includeField])
        grid.addRow(with: [label("排除:"), excludeField])
        grid.addRow(with: [label("参数:"), paramsField])
        grid.addRow(with: [flatModeButton])
        grid.column(at: 0).xPlacement = .trailing

        // Scrollable content: buttons stay visible at any window size
        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        let header = label("解压压缩包: \(archive.lastPathComponent)")
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        contentStack.addArrangedSubview(header)
        contentStack.addArrangedSubview(grid)

        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 10),
            contentStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -12),
            contentStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -10),
        ])

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc
        doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.addView(cancel, in: .leading)
        row.addView(ok, in: .trailing)
        row.translatesAutoresizingMaskIntoConstraints = false

        cv.addSubview(scroll)
        cv.addSubview(row)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: cv.topAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: row.topAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -12),
            destField.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
        ])
    }

    @objc func browseDest() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "选择解压目标文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            destField.stringValue = url.path
        }
    }

    func runModal(on window: NSWindow?, completion: @escaping () -> Void) {
        self.completion = completion
        guard let w = self.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: w)
    }

    @objc func okClick() {
        let dest = URL(fileURLWithPath: destField.stringValue)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        var pathMode = ""
        switch pathModePopup.indexOfSelectedItem {
        case 1: pathMode = "-ep"
        case 2: pathMode = "-ep1"
        case 3: pathMode = "-ep2"
        default: break
        }
        var overwrite = ""
        switch overwritePopup.indexOfSelectedItem {
        case 1: overwrite = "-aos"
        case 2: overwrite = "-aou"
        case 3: overwrite = "-aot"
        default: overwrite = "-aoa"
        }
        var extra = paramsField.stringValue
        func appendPatterns(_ text: String, prefix: String) {
            for part in text.split(whereSeparator: { $0 == ";" || $0 == "," }) {
                let p = part.trimmingCharacters(in: .whitespaces)
                if !p.isEmpty { extra += " \(prefix)!\(p)" }
            }
        }
        appendPatterns(includeField.stringValue, prefix: "-i")
        appendPatterns(excludeField.stringValue, prefix: "-x")

        let args = ArgsBuilder.extract(
            archivePath: archive,
            files: files,
            destDir: dest,
            password: passwordField.stringValue.isEmpty ? nil : passwordField.stringValue,
            pathMode: pathMode,
            overwrite: overwrite,
            extraParams: extra,
            extractWithoutPaths: flatModeButton.state == .on
        )
        window?.orderOut(nil)
        NSApp.stopModal()
        let onFinish = self.completion
        OperationRunner.shared.start(args: args, title: "解压: \(archive.lastPathComponent)", window: window) { _, _ in
            onFinish?()
        }
    }

    @objc func cancelClick() {
        window?.orderOut(nil)
        NSApp.stopModal()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancelClick()
        return true
    }
}