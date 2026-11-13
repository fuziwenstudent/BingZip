import AppKit

/// Button carrying an arbitrary payload (used for breadcrumb targets).
final class CrumbButton: NSButton {
    var payload: Any?
}

/// 7-Zip style address bar with clickable breadcrumbs, history buttons and location shortcuts.
final class PathBarView: NSView, NSTextFieldDelegate {

    // Callbacks
    var onUp: (() -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onNavigate: ((URL) -> Void)?                    // file-system folder
    var onNavigateArchive: ((URL, String) -> Void)?     // archive + inner path
    var onPickLocation: ((String) -> Void)?             // path string from menu / editor
    var onToggleSidebar: (() -> Void)?

    // UI
    private var sidebarButton: NSButton!
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var upButton: NSButton!
    private var crumbStack: NSStackView!
    private var pathField: NSTextField!
    private var locationButton: NSButton!
    private var editButton: NSButton!

    private var currentLocation: PanelLocation = .folder(URL(fileURLWithPath: NSHomeDirectory()))
    private var isEditing = false
    private var lastBuiltWidth: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
        update(location: currentLocation, canGoBack: false, canGoForward: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        guard !isEditing else { return }
        let w = bounds.width
        if abs(w - lastBuiltWidth) > 40 {
            lastBuiltWidth = w
            rebuildCrumbs()
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        sidebarButton = iconButton("sidebar.left", tooltip: "显示 / 隐藏侧边栏", action: #selector(toggleSidebarClicked))
        backButton = iconButton("chevron.left", tooltip: "后退", action: #selector(backClicked))
        forwardButton = iconButton("chevron.right", tooltip: "前进", action: #selector(forwardClicked))
        upButton = iconButton("arrow.up", tooltip: "上一级", action: #selector(upClicked))
        locationButton = iconButton("star", tooltip: "常用位置", action: #selector(showLocations(_:)))
        editButton = iconButton("pencil", tooltip: "编辑路径", action: #selector(editClicked))

        crumbStack = NSStackView()
        crumbStack.orientation = .horizontal
        crumbStack.spacing = 2
        crumbStack.alignment = .centerY
        crumbStack.translatesAutoresizingMaskIntoConstraints = false

        pathField = NSTextField()
        pathField.font = .systemFont(ofSize: 12)
        pathField.bezelStyle = .roundedBezel
        pathField.isHidden = true
        pathField.target = self
        pathField.action = #selector(pathFieldEnter)
        pathField.delegate = self
        pathField.translatesAutoresizingMaskIntoConstraints = false

        let bar = NSStackView(views: [sidebarButton, backButton, forwardButton, upButton, crumbStack, pathField, locationButton, editButton])
        bar.orientation = .horizontal
        bar.spacing = 4
        bar.alignment = .centerY
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.setHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(bar)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            crumbStack.heightAnchor.constraint(equalToConstant: 20),
            pathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
    }

    private func iconButton(_ symbol: String, tooltip: String, action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage(),
                         target: self, action: action)
        b.bezelStyle = .inline
        b.isBordered = false
        b.toolTip = tooltip
        b.imageScaling = .scaleProportionallyDown
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 20).isActive = true
        b.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return b
    }

    // MARK: - Public update

    func update(location: PanelLocation, canGoBack: Bool = false, canGoForward: Bool = false) {
        currentLocation = location
        crumbStack.isHidden = false
        pathField.isHidden = true
        isEditing = false
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
        upButton.isEnabled = true
        rebuildCrumbs()
    }

    var displayPath: String {
        switch currentLocation {
        case .folder(let url): return url.path
        case .archive(let url, let inner): return url.path + "//" + inner
        }
    }

    // MARK: - Breadcrumbs

    private func addCrumb(_ title: String, tooltip: String, action: Selector, represented: Any?, isLast: Bool) {
        let b = CrumbButton(title: title, target: self, action: action)
        b.bezelStyle = .inline
        b.isBordered = false
        b.font = .systemFont(ofSize: 12, weight: isLast ? .semibold : .regular)
        b.contentTintColor = isLast ? .labelColor : .controlAccentColor
        b.toolTip = tooltip
        b.lineBreakMode = .byTruncatingMiddle
        b.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        b.payload = represented
        crumbStack.addArrangedSubview(b)
        if !isLast {
            let sep = NSTextField(labelWithString: "›")
            sep.font = .systemFont(ofSize: 11)
            sep.textColor = .tertiaryLabelColor
            crumbStack.addArrangedSubview(sep)
        }
    }

    private func addEllipsis(ancestors: [(String, String)]) {
        let b = CrumbButton(title: "…", target: self, action: #selector(ellipsisClicked(_:)))
        b.bezelStyle = .inline
        b.isBordered = false
        b.font = .systemFont(ofSize: 12)
        b.contentTintColor = .controlAccentColor
        b.toolTip = "更上层文件夹"
        b.payload = ancestors
        crumbStack.addArrangedSubview(b)
        let sep = NSTextField(labelWithString: "›")
        sep.font = .systemFont(ofSize: 11)
        sep.textColor = .tertiaryLabelColor
        crumbStack.addArrangedSubview(sep)
    }

    private func rebuildCrumbs() {
        for v in crumbStack.arrangedSubviews {
            crumbStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        switch currentLocation {
        case .folder(let url):
            addCrumb("🖥", tooltip: "/", action: #selector(crumbClicked(_:)),
                     represented: "/", isLast: url.path == "/")
            let comps = url.pathComponents.filter { $0 != "/" }
            guard !comps.isEmpty else { return }

            let maxVisible = maxVisibleCrumbs()
            if comps.count > maxVisible {
                var ancestors: [(String, String)] = []
                var acc = ""
                for (i, c) in comps.enumerated() {
                    acc = acc.isEmpty ? "/" + c : acc + "/" + c
                    if i < comps.count - maxVisible {
                        ancestors.append((c, acc))
                    }
                }
                addEllipsis(ancestors: ancestors)
                var prefix = ""
                for i in 0..<(comps.count - maxVisible) {
                    prefix = prefix.isEmpty ? "/" + comps[i] : prefix + "/" + comps[i]
                }
                var path = prefix
                let tail = Array(comps.suffix(maxVisible))
                for (j, c) in tail.enumerated() {
                    path = path.isEmpty ? "/" + c : path + "/" + c
                    addCrumb(c, tooltip: path, action: #selector(crumbClicked(_:)),
                             represented: path, isLast: j == tail.count - 1)
                }
            } else {
                var acc = ""
                for (i, c) in comps.enumerated() {
                    acc = acc.isEmpty ? "/" + c : acc + "/" + c
                    addCrumb(c, tooltip: acc, action: #selector(crumbClicked(_:)),
                             represented: acc, isLast: i == comps.count - 1)
                }
            }

        case .archive(let url, let inner):
            addCrumb(url.lastPathComponent, tooltip: url.path + "//",
                     action: #selector(archiveRootClicked(_:)), represented: url, isLast: inner.isEmpty)
            let parts = inner.split(separator: "/").map(String.init)
            guard !parts.isEmpty else { return }
            let maxVisible = maxVisibleCrumbs()
            if parts.count > maxVisible {
                var ancestors: [String] = []
                var prefix = ""
                for i in 0..<(parts.count - maxVisible) {
                    prefix = prefix.isEmpty ? parts[i] : prefix + "/" + parts[i]
                    ancestors.append(prefix)
                }
                addArchiveEllipsis(archive: url, innerPaths: ancestors)
                var acc = prefix
                let tail = Array(parts.suffix(maxVisible))
                for (j, p) in tail.enumerated() {
                    acc = acc.isEmpty ? p : acc + "/" + p
                    addCrumb(p, tooltip: "\(url.lastPathComponent)//\(acc)",
                             action: #selector(archiveInnerClicked(_:)),
                             represented: (url, acc), isLast: j == tail.count - 1)
                }
            } else {
                var acc = ""
                for (i, p) in parts.enumerated() {
                    acc = acc.isEmpty ? p : acc + "/" + p
                    addCrumb(p, tooltip: "\(url.lastPathComponent)//\(acc)",
                             action: #selector(archiveInnerClicked(_:)),
                             represented: (url, acc), isLast: i == parts.count - 1)
                }
            }
        }
    }

    /// Number of breadcrumb segments to show based on the current width.
    private func maxVisibleCrumbs() -> Int {
        let w = bounds.width
        if w > 470 { return 5 }
        if w > 380 { return 4 }
        if w > 300 { return 3 }
        if w > 220 { return 2 }
        return 1
    }

    private func addArchiveEllipsis(archive: URL, innerPaths: [String]) {
        let b = CrumbButton(title: "…", target: self, action: #selector(archiveEllipsisClicked(_:)))
        b.bezelStyle = .inline
        b.isBordered = false
        b.font = .systemFont(ofSize: 12)
        b.contentTintColor = .controlAccentColor
        b.toolTip = "更上层文件夹"
        b.payload = innerPaths.map { "\(archive.path)//\($0)" }
        crumbStack.addArrangedSubview(b)
        let sep = NSTextField(labelWithString: "›")
        sep.font = .systemFont(ofSize: 11)
        sep.textColor = .tertiaryLabelColor
        crumbStack.addArrangedSubview(sep)
    }

    // MARK: - Breadcrumb actions

    @objc func crumbClicked(_ sender: NSButton) {
        guard let b = sender as? CrumbButton, let path = b.payload as? String else { return }
        onNavigate?(URL(fileURLWithPath: path))
    }

    @objc func ellipsisClicked(_ sender: NSButton) {
        guard let b = sender as? CrumbButton,
              let ancestors = b.payload as? [(String, String)], !ancestors.isEmpty else { return }
        let menu = NSMenu()
        for (title, path) in ancestors {
            let item = NSMenuItem(title: title, action: #selector(ancestorPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = path
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc func ancestorPicked(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        onNavigate?(URL(fileURLWithPath: path))
    }

    @objc func archiveRootClicked(_ sender: NSButton) {
        guard let b = sender as? CrumbButton, let url = b.payload as? URL else { return }
        onNavigateArchive?(url, "")
    }

    @objc func archiveInnerClicked(_ sender: NSButton) {
        guard let b = sender as? CrumbButton, let pair = b.payload as? (URL, String) else { return }
        onNavigateArchive?(pair.0, pair.1)
    }

    @objc func archiveEllipsisClicked(_ sender: NSButton) {
        guard let b = sender as? CrumbButton, let items = b.payload as? [String], !items.isEmpty else { return }
        let menu = NSMenu()
        for s in items {
            guard let r = s.range(of: "//") else { continue }
            let inner = String(s[r.upperBound...])
            let item = NSMenuItem(title: inner, action: #selector(archiveEllipsisPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc func archiveEllipsisPicked(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String,
              let r = s.range(of: "//") else { return }
        onNavigateArchive?(URL(fileURLWithPath: String(s[..<r.lowerBound])),
                           String(s[r.upperBound...]))
    }

    @objc func toggleSidebarClicked() {
        onToggleSidebar?()
    }

    // MARK: - History / up

    @objc func backClicked() { onBack?() }
    @objc func forwardClicked() { onForward?() }
    @objc func upClicked() { onUp?() }

    // MARK: - Location shortcuts

    @objc func showLocations(_ sender: NSButton) {
        let menu = NSMenu()
        let home = NSHomeDirectory()
        let places: [(String, String)] = [
            ("主目录", home),
            ("桌面", home + "/Desktop"),
            ("下载", home + "/Downloads"),
            ("文稿", home + "/Documents"),
            ("应用程序", "/Applications"),
            ("根目录", "/"),
        ]
        for (title, path) in places {
            let item = NSMenuItem(title: title, action: #selector(locationPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = path
            menu.addItem(item)
        }
        let bookmarks = UserDefaults.standard.stringArray(forKey: "BingZipBookmarks") ?? []
        if !bookmarks.isEmpty {
            menu.addItem(.separator())
            for b in bookmarks {
                let item = NSMenuItem(title: "📁 " + b, action: #selector(locationPicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = b
                menu.addItem(item)
            }
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc func locationPicked(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        onPickLocation?(path)
    }

    // MARK: - Path editing

    @objc func editClicked() {
        guard !isEditing else { finishEdit(); return }
        isEditing = true
        crumbStack.isHidden = true
        pathField.isHidden = false
        pathField.stringValue = displayPath
        window?.makeFirstResponder(pathField)
        pathField.currentEditor()?.selectAll(nil)
    }

    @objc func pathFieldEnter() {
        let text = pathField.stringValue.trimmingCharacters(in: .whitespaces)
        defer { finishEdit() }
        guard !text.isEmpty else { return }
        let expanded = (text as NSString).expandingTildeInPath
        if let range = expanded.range(of: "//") {
            let archivePath = String(expanded[..<range.lowerBound])
            let inner = String(expanded[range.upperBound...])
            onNavigateArchive?(URL(fileURLWithPath: archivePath), inner)
        } else {
            onPickLocation?(expanded)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishEdit()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if (obj.object as? NSTextField) === pathField {
            finishEdit()
        }
    }

    private func finishEdit() {
        isEditing = false
        pathField.isHidden = true
        crumbStack.isHidden = false
        rebuildCrumbs()
    }
}