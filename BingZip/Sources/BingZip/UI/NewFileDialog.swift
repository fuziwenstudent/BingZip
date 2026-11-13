import AppKit

/// “新建空白文件”对话框:输入文件名与后缀,返回 "名称.后缀"
final class NewFileDialog: NSWindowController, NSWindowDelegate {

    private var nameField: NSTextField!
    private var extField: NSTextField!
    private var result: String?

    init(defaultName: String = "新建文件") {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 176),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "新建文件"
        super.init(window: w)
        w.delegate = self
        setup(defaultName: defaultName)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup(defaultName: String) {
        guard let cv = window?.contentView else { return }

        let nameLabel = NSTextField(labelWithString: "文件名称:")
        nameLabel.font = .systemFont(ofSize: 12)
        nameField = NSTextField()
        nameField.stringValue = defaultName
        nameField.font = .systemFont(ofSize: 12)
        nameField.placeholderString = "例如: 我的笔记"

        let extLabel = NSTextField(labelWithString: "后缀名:")
        extLabel.font = .systemFont(ofSize: 12)
        extField = NSTextField()
        extField.stringValue = "txt"
        extField.font = .systemFont(ofSize: 12)
        extField.placeholderString = "例如: txt(可留空)"

        let hint = NSTextField(labelWithString: "将创建一个内容为空的文件。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let ok = NSButton(title: "确定", target: self, action: #selector(okClick))
        ok.keyEquivalent = "\r"
        ok.bezelStyle = .rounded
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelClick))
        cancel.keyEquivalent = "\u{1b}"
        cancel.bezelStyle = .rounded

        let grid = NSGridView(views: [
            [nameLabel, nameField],
            [extLabel, extField],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [cancel, ok])
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        cv.addSubview(grid)
        cv.addSubview(hint)
        cv.addSubview(row)
        hint.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: cv.topAnchor, constant: 18),
            grid.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 18),
            grid.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -18),
            nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            extField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),

            hint.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 10),
            hint.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 18),

            row.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -14),
            row.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -18),
        ])
    }

    func runModal(on parent: NSWindow?) -> String? {
        guard let w = window else { return nil }
        w.center()
        NSApp.runModal(for: w)
        return result
    }

    @objc func okClick() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        var ext = extField.stringValue.trimmingCharacters(in: .whitespaces)
        if ext.hasPrefix(".") { ext.removeFirst() }
        guard !name.isEmpty else { NSSound.beep(); return }
        result = ext.isEmpty ? name : "\(name).\(ext)"
        window?.orderOut(nil)
        NSApp.stopModal()
    }

    @objc func cancelClick() {
        result = nil
        window?.orderOut(nil)
        NSApp.stopModal()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancelClick()
        return true
    }
}
