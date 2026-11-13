import AppKit

/// Shows the full format capabilities reported by `7zz i` (supported archives/codecs).
final class FormatInfoDialog: NSWindowController, NSWindowDelegate {

    private var textView: NSTextView!

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 540),
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "BingZip 支持的格式"
        super.init(window: w)
        w.delegate = self
        buildContent()
        loadFormats()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildContent() {
        guard let cv = window?.contentView else { return }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = "正在读取引擎格式信息…"
        scroll.documentView = textView

        let close = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
        close.keyEquivalent = "\r"
        close.bezelStyle = .rounded

        let sv = NSStackView()
        sv.orientation = .vertical
        sv.spacing = 10
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.addArrangedSubview(scroll)
        sv.addArrangedSubview(close)
        cv.addSubview(sv)
        NSLayoutConstraint.activate([
            sv.topAnchor.constraint(equalTo: cv.topAnchor, constant: 12),
            sv.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            sv.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            sv.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -12),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 440),
        ])
    }

    private func loadFormats() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = try? SevenZip.shared.run(["i"])
            DispatchQueue.main.async {
                let text = (result?.stdout ?? "") + (result?.stderr ?? "")
                RarTool.shared.reload()
                let rarLine: String
                if RarTool.shared.isAvailable, let url = RarTool.shared.binaryURL {
                    rarLine = "RAR 创建:可用 —— \(url.path)"
                } else {
                    rarLine = "RAR 创建:未安装 RARLAB rar 工具(内置 7-Zip 引擎只能解压 RAR)"
                }
                self?.textView.string = rarLine + "\n\n" + (text.isEmpty ? "无法读取格式信息" : text)
            }
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