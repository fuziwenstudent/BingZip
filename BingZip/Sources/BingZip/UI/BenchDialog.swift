import AppKit

/// 7-Zip style benchmark dialog.
final class BenchDialog: NSWindowController, NSWindowDelegate {

    private var dictPopup: NSPopUpButton!
    private var threadsPopup: NSPopUpButton!
    private var outputView: NSTextView!
    private var cancelButton: NSButton!

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        w.contentMinSize = NSSize(width: 520, height: 360)
        w.title = "基准测试"
        super.init(window: w)
        w.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildContent() {
        guard let cv = window?.contentView else { return }

        dictPopup = NSPopUpButton()
        dictPopup.addItems(withTitles: ["1m", "2m", "4m", "8m", "16m", "32m", "64m"])
        dictPopup.selectItem(at: 5)
        threadsPopup = NSPopUpButton()
        threadsPopup.addItems(withTitles: ["(默认)", "1", "2", "4", "8"])
        threadsPopup.selectItem(at: 0)

        let run = NSButton(title: "开始", target: self, action: #selector(runBench))
        run.bezelStyle = .rounded
        cancelButton = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
        cancelButton.bezelStyle = .rounded

        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.spacing = 8
        let dictLabel = NSTextField(labelWithString: "字典大小:")
        let threadLabel = NSTextField(labelWithString: "线程数:")
        dictLabel.font = .systemFont(ofSize: 12)
        threadLabel.font = .systemFont(ofSize: 12)
        controls.addView(dictLabel, in: .leading)
        controls.addView(dictPopup, in: .leading)
        controls.addView(threadLabel, in: .leading)
        controls.addView(threadsPopup, in: .leading)
        controls.addView(run, in: .leading)
        controls.addView(cancelButton, in: .trailing)

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
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
        ])
    }

    @objc func runBench() {
        var args = ["b"]
        if let t = threadsPopup.titleOfSelectedItem, let n = Int(t) { args.append("-mmt=\(n)") }
        args.append("-md=\(dictPopup.titleOfSelectedItem ?? "32m")")
        outputView.string = "正在运行基准测试…\n"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = try? SevenZip.shared.run(args, onLine: { line in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.outputView.string += line + "\n"
                    self.outputView.scrollToEndOfDocument(nil)
                }
            })
            DispatchQueue.main.async {
                let out = (result?.stdout ?? "") + (result?.stderr ?? "")
                self?.outputView.string += out
                self?.outputView.scrollToEndOfDocument(nil)
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