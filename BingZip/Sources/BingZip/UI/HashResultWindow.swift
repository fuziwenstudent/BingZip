import AppKit

/// Shows MD5 / SHA256 of a freshly created archive with one-click copy.
final class HashResultWindow: NSWindowController, NSWindowDelegate {

    private static var openWindows: [HashResultWindow] = []

    private let archiveURL: URL
    private var md5Field: NSTextField!
    private var sha256Field: NSTextField!
    private var copyMD5Button: NSButton!
    private var copySHAButton: NSButton!
    private var copyAllButton: NSButton!

    init(archiveURL: URL) {
        self.archiveURL = archiveURL
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 300),
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "压缩完成 — 校验信息"
        w.contentMinSize = NSSize(width: 560, height: 280)
        super.init(window: w)
        w.delegate = self
        HashResultWindow.openWindows.append(self)
        buildContent()
        computeHashes()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func label(_ text: String, size: CGFloat = 12, bold: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        return l
    }

    private func hashField() -> NSTextField {
        let f = NSTextField(labelWithString: "计算中…")
        f.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        f.isSelectable = true
        f.lineBreakMode = .byTruncatingMiddle
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }

    private func buildContent() {
        guard let cv = window?.contentView else { return }

        let nameLabel = label(archiveURL.lastPathComponent, size: 14, bold: true)
        let size = (try? archiveURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let infoLabel = label("大小: \(formatBytes(Int64(size)))   位置: \(archiveURL.deletingLastPathComponent().path)",
                              size: 11)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.lineBreakMode = .byTruncatingMiddle

        md5Field = hashField()
        sha256Field = hashField()

        copyMD5Button = NSButton(title: "复制 MD5", target: self, action: #selector(copyMD5))
        copyMD5Button.bezelStyle = .rounded
        copyMD5Button.isEnabled = false
        copySHAButton = NSButton(title: "复制 SHA256", target: self, action: #selector(copySHA))
        copySHAButton.bezelStyle = .rounded
        copySHAButton.isEnabled = false
        copyAllButton = NSButton(title: "复制全部", target: self, action: #selector(copyAll))
        copyAllButton.bezelStyle = .rounded
        copyAllButton.isEnabled = false

        let grid = NSGridView(views: [
            [label("MD5:", bold: true), md5Field, copyMD5Button],
            [label("SHA256:", bold: true), sha256Field, copySHAButton],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing

        let showInFinder = NSButton(title: "在 Finder 中显示", target: self, action: #selector(showInFinder))
        showInFinder.bezelStyle = .rounded
        let close = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
        close.keyEquivalent = "\u{1b}"
        close.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [showInFinder, copyAllButton, close])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let sv = NSStackView(views: [nameLabel, infoLabel, grid, buttonRow])
        sv.orientation = .vertical
        sv.alignment = .leading
        sv.spacing = 12
        sv.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(sv)
        NSLayoutConstraint.activate([
            sv.topAnchor.constraint(equalTo: cv.topAnchor, constant: 18),
            sv.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            sv.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),
            sv.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor, constant: -16),
            md5Field.widthAnchor.constraint(greaterThanOrEqualToConstant: 380),
            sha256Field.widthAnchor.constraint(greaterThanOrEqualToConstant: 380),
        ])
    }

    private func computeHashes() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let md5 = Self.computeHash("MD5", archive: self.archiveURL)
            let sha = Self.computeHash("SHA256", archive: self.archiveURL)
            DispatchQueue.main.async {
                self.md5Field.stringValue = md5 ?? "计算失败"
                self.sha256Field.stringValue = sha ?? "计算失败"
                self.copyMD5Button.isEnabled = (md5 != nil)
                self.copySHAButton.isEnabled = (sha != nil)
                self.copyAllButton.isEnabled = (md5 != nil || sha != nil)
            }
        }
    }

    static func computeHash(_ type: String, archive: URL) -> String? {
        guard let r = try? SevenZip.shared.run(["h", "-slt", "-scrc\(type)", archive.path]) else { return nil }
        let out = r.stdout + "\n" + r.stderr
        let pattern = type + #"\s+for data:\s*([0-9a-fA-F]+)"#
        guard let range = out.range(of: pattern, options: .regularExpression) else { return nil }
        let line = String(out[range])
        guard let colon = line.range(of: ":") else { return nil }
        return String(line[colon.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyToPasteboard(_ text: String) {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    @objc func copyMD5() { copyToPasteboard(md5Field.stringValue) }
    @objc func copySHA() { copyToPasteboard(sha256Field.stringValue) }

    @objc func copyAll() {
        let text = """
        \(archiveURL.lastPathComponent)
        MD5:    \(md5Field.stringValue)
        SHA256: \(sha256Field.stringValue)
        """
        copyToPasteboard(text)
    }

    @objc func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([archiveURL])
    }

    @objc func closeWindow() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        HashResultWindow.openWindows.removeAll { $0 === self }
    }
}