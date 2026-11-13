import AppKit

/// CRC / hash calculation dialog (7-Zip "Calculate CRC" feature).
final class HashDialog: NSWindowController, NSWindowDelegate {

    private var hashPopup: NSPopUpButton!
    private var outputView: NSTextView!

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        w.contentMinSize = NSSize(width: 520, height: 320)
        w.title = "计算 CRC / 哈希"
        super.init(window: w)
        w.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildContent() {
        guard let cv = window?.contentView else { return }

        hashPopup = NSPopUpButton()
        hashPopup.addItems(withTitles: ["CRC32", "CRC64", "SHA1", "SHA256", "BLAKE2sp", "XXH64", "*"])
        hashPopup.selectItem(at: 0)

        let pick = NSButton(title: "选择文件…", target: self, action: #selector(pickFile))
        pick.bezelStyle = .rounded
        let close = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
        close.bezelStyle = .rounded

        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.spacing = 8
        let hashLabel = NSTextField(labelWithString: "哈希类型:")
        hashLabel.font = .systemFont(ofSize: 12)
        controls.addView(hashLabel, in: .leading)
        controls.addView(hashPopup, in: .leading)
        controls.addView(pick, in: .leading)
        controls.addView(close, in: .trailing)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        outputView = NSTextView()
        outputView.isEditable = false
        outputView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        scroll.documentView = outputView

        let sv = NSStackView()
        sv.orientation = .vertical
        sv.spacing = 10
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.addArrangedSubview(controls)
        sv.addArrangedSubview(scroll)
        cv.addSubview(sv)
        NSLayoutConstraint.activate([
            sv.topAnchor.constraint(equalTo: cv.topAnchor, constant: 12),
            sv.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            sv.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            sv.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -12),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
        ])
    }

    @objc func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "选择要计算哈希的文件或文件夹"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            run(urls: panel.urls)
        }
    }

    private func run(urls: [URL]) {
        let hashType = hashPopup.titleOfSelectedItem ?? "CRC32"
        var args = ["h", "-scrc\(hashType)"]
        args.append(contentsOf: urls.map { $0.path })
        outputView.string = "正在计算 \(hashType)…\n"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = try? SevenZip.shared.run(args)
            DispatchQueue.main.async {
                let out = result?.stdout ?? ""
                let err = result?.stderr ?? ""
                let combined = (out + err)
                self?.outputView.string = combined
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