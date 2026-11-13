import AppKit

/// 7-Zip style "Add to archive" dialog with the full parameter set.
final class AddDialog: NSWindowController, NSWindowDelegate {

    let sources: [URL]
    var completion: (() -> Void)?

    var archiveField: NSTextField!
    var updatePopup: NSPopUpButton!
    var formatPopup: NSPopUpButton!
    var levelPopup: NSPopUpButton!
    var methodPopup: NSPopUpButton!
    var dictPopup: NSPopUpButton!
    var wordField: NSTextField!
    var threadsPopup: NSPopUpButton!
    var solidPopup: NSPopUpButton!
    var memLabel: NSTextField!
    var passwordField: NSSecureTextField!
    var password2Field: NSSecureTextField!
    var encryptHeaderButton: NSButton!
    var volumeField: NSTextField!
    var volumeUnitPopup: NSPopUpButton!
    var pathModePopup: NSPopUpButton!
    var paramsField: NSTextField!
    var deleteSourceButton: NSButton!
    var symlinkButton: NSButton!
    var excludeField: NSTextField!
    var hintLabel: NSTextField!
    var twoCols: NSStackView!

    init(sources: [URL], suggestDirectory: URL) {
        self.sources = sources
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 380),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.contentMinSize = NSSize(width: 560, height: 350)
        w.title = "压缩"
        super.init(window: w)
        w.delegate = self
        setup(suggest: suggestDirectory)
    }

    required init?(coder: NSCoder) { fatalError() }

    func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12)
        return l
    }

    func comboBox(_ items: [String], select: Int = 0) -> NSPopUpButton {
        let p = NSPopUpButton()
        p.addItems(withTitles: items)
        p.selectItem(at: select)
        return p
    }

    func runModal(on window: NSWindow?, completion: @escaping () -> Void) {
        self.completion = completion
        guard let w = self.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: w)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancelClick()
        return true
    }

    // MARK: - Responsive layout

    func windowDidResize(_ notification: Notification) {
        updateResponsiveLayout()
    }

    /// Two columns on wide windows, single column on narrow ones.
    func updateResponsiveLayout() {
        guard let cv = window?.contentView, let two = twoCols else { return }
        let vertical = cv.bounds.width < 760
        if (two.orientation == .horizontal) == vertical {
            two.orientation = vertical ? .vertical : .horizontal
            two.spacing = vertical ? 14 : 24
            two.alignment = .leading
        }
    }
}