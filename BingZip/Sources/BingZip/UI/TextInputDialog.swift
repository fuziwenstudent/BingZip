import AppKit

/// Simple text-input dialog (used for rename / new folder / password).
final class TextInputDialog: NSWindowController, NSWindowDelegate {

    private var input: NSTextField!
    private var result: String?
    private let prompt: String
    private let isSecure: Bool

    init(title: String, prompt: String, defaultValue: String, secure: Bool = false) {
        self.prompt = prompt
        self.isSecure = secure
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 130),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = title
        super.init(window: w)
        w.delegate = self
        setup(defaultValue: defaultValue)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup(defaultValue: String) {
        guard let cv = window?.contentView else { return }
        let label = NSTextField(labelWithString: prompt)
        label.font = .systemFont(ofSize: 12)
        input = isSecure ? NSSecureTextField() : NSTextField()
        input.stringValue = defaultValue
        input.font = .systemFont(ofSize: 12)
        let ok = NSButton(title: "确定", target: self, action: #selector(okClick))
        ok.keyEquivalent = "\r"
        ok.bezelStyle = .rounded
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelClick))
        cancel.keyEquivalent = "\u{1b}"
        cancel.bezelStyle = .rounded

        let sv = NSStackView()
        sv.orientation = .vertical
        sv.spacing = 10
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.addArrangedSubview(label)
        sv.addArrangedSubview(input)
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.addView(cancel, in: .leading)
        row.addView(ok, in: .trailing)
        sv.addArrangedSubview(row)
        cv.addSubview(sv)
        NSLayoutConstraint.activate([
            sv.topAnchor.constraint(equalTo: cv.topAnchor, constant: 14),
            sv.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            sv.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            sv.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor, constant: -12),
            input.widthAnchor.constraint(greaterThanOrEqualToConstant: 340),
        ])
    }

    func runModal(on parent: NSWindow?) -> String? {
        guard let w = window else { return nil }
        w.center()
        NSApp.runModal(for: w)
        return result
    }

    @objc func okClick() {
        result = input.stringValue
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