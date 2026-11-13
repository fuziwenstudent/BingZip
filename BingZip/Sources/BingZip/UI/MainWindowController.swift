import AppKit

/// Bandizip 风格主窗口:大图标工具栏 + 左侧目录树 + 右侧文件列表。
final class MainWindowController: NSWindowController, NSWindowDelegate {

    /// 主文件列表(单面板,Bandizip 风格)
    var leftPanel: FilePanel!
    /// 兼容旧接口保留;不参与界面显示
    var rightPanel: FilePanel!

    var tree: ArchiveTreeView!
    private var toolbarBar: NSView!
    private var tabBar: NSView!
    private var tabIcon: NSImageView!
    private var tabLabel: NSTextField!
    private var dividerView: NSView!
    private var treeWidth: NSLayoutConstraint!

    var activePanel: FilePanel { leftPanel }

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1220, height: 740),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "BingZip"
        w.contentMinSize = NSSize(width: 820, height: 480)
        super.init(window: w)
        w.delegate = self
        buildContent()
        w.center()
        DispatchQueue.main.async { [weak self] in
            self?.focusInitialResponder()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // Bandizip 风格的功能位:打开 / 解压 / 新建 / 删除 / 测试
    // “扫描”已并入“测试”:未选中压缩包时自动扫描当前文件夹。
    // “代码页”已并入版本信息窗口;版本信息仍可从帮助 / 应用菜单打开。
    static let defaultItems: [(String, String, Selector)] = [
        ("打开", "folder", #selector(openAction)),
        ("解压", "archivebox", #selector(extractAction)),
        ("新建", "doc.badge.plus", #selector(newArchiveAction)),
        ("删除", "trash", #selector(deleteAction)),
        ("测试", "bolt", #selector(testAction)),
    ]


    // MARK: - Layout

    private func buildContent() {
        guard let cv = window?.contentView else { return }

        tabBar = buildTabBar()
        toolbarBar = buildToolbarBar()

        tree = ArchiveTreeView()
        tree.translatesAutoresizingMaskIntoConstraints = false

        leftPanel = FilePanel(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        leftPanel.translatesAutoresizingMaskIntoConstraints = false
        leftPanel.setSidebarVisible(false)
        leftPanel.onLocationChange = { [weak self] loc in
            self?.syncUI(with: loc)
        }
        // 路径栏的侧边栏按钮改为控制左侧目录树
        leftPanel.pathBar.onToggleSidebar = { [weak self] in
            guard let self = self, let tree = self.tree else { return }
            let next = tree.isHidden
            UserDefaults.standard.set(next, forKey: "BingZipShowTree")
            self.showTree(next)
        }

        rightPanel = FilePanel(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        rightPanel.setSidebarVisible(false)

        tree.onSelectPath = { [weak self] path in
            self?.leftPanel.navigate(toFile: URL(fileURLWithPath: path))
        }
        tree.onSelectInnerPath = { [weak self] inner in
            self?.leftPanel.goToInnerPath(inner)
        }
        tree.onSwipeBack = { [weak self] in self?.leftPanel.goBack() }
        tree.onSwipeForward = { [weak self] in self?.leftPanel.goForward() }

        // 使用普通容器而不是 NSSplitView:后者与 Auto Layout 子视图组合会触发布局死循环
        let body = NSView()
        body.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        dividerView = divider

        body.addSubview(tree)
        body.addSubview(divider)
        body.addSubview(leftPanel)

        cv.addSubview(toolbarBar)
        cv.addSubview(tabBar)
        cv.addSubview(body)

        treeWidth = tree.widthAnchor.constraint(equalToConstant: 220)

        NSLayoutConstraint.activate([
            toolbarBar.topAnchor.constraint(equalTo: cv.topAnchor),
            toolbarBar.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            toolbarBar.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            toolbarBar.heightAnchor.constraint(equalToConstant: 60),

            tabBar.topAnchor.constraint(equalTo: toolbarBar.bottomAnchor),
            tabBar.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 24),

            body.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: cv.bottomAnchor),

            tree.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            tree.topAnchor.constraint(equalTo: body.topAnchor),
            tree.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            treeWidth,

            divider.leadingAnchor.constraint(equalTo: tree.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.topAnchor.constraint(equalTo: body.topAnchor),
            divider.bottomAnchor.constraint(equalTo: body.bottomAnchor),

            leftPanel.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            leftPanel.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            leftPanel.topAnchor.constraint(equalTo: body.topAnchor),
            leftPanel.bottomAnchor.constraint(equalTo: body.bottomAnchor),
        ])

        DispatchQueue.main.async { [weak self] in
            if let loc = self?.leftPanel.location { self?.syncUI(with: loc) }
            let showTree = UserDefaults.standard.object(forKey: "BingZipShowTree") as? Bool ?? true
            self?.showTree(showTree)
        }
    }

    private func buildToolbarBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (label, symbol, action) in Self.defaultItems {
            let b = NSButton(title: label, target: self, action: action)
            b.isBordered = false
            b.bezelStyle = .regularSquare
            b.imagePosition = .imageAbove
            let cfg = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                .withSymbolConfiguration(cfg)
            b.contentTintColor = .controlAccentColor
            b.font = .systemFont(ofSize: 11)
            b.toolTip = label == "测试" ? "测试压缩包 / 扫描当前文件夹" : label
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 64).isActive = true
            b.heightAnchor.constraint(equalToConstant: 52).isActive = true
            stack.addArrangedSubview(b)
        }

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(stack)
        bar.addSubview(sep)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -8),
            sep.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])
        return bar
    }

    private func buildTabBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false

        tabIcon = NSImageView()
        tabIcon.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
        tabIcon.contentTintColor = .controlAccentColor
        tabIcon.translatesAutoresizingMaskIntoConstraints = false

        tabLabel = NSTextField(labelWithString: "BingZip")
        tabLabel.font = .systemFont(ofSize: 11, weight: .medium)
        tabLabel.lineBreakMode = .byTruncatingMiddle
        tabLabel.translatesAutoresizingMaskIntoConstraints = false

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(tabIcon)
        bar.addSubview(tabLabel)
        bar.addSubview(sep)
        NSLayoutConstraint.activate([
            tabIcon.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
            tabIcon.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            tabIcon.widthAnchor.constraint(equalToConstant: 14),
            tabIcon.heightAnchor.constraint(equalToConstant: 14),
            tabLabel.leadingAnchor.constraint(equalTo: tabIcon.trailingAnchor, constant: 6),
            tabLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            tabLabel.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -8),
            sep.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])
        return bar
    }

    /// 同步标题、标签页与左侧目录树
    private func syncUI(with location: PanelLocation) {
        switch location {
        case .folder(let url):
            let name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
            tabLabel?.stringValue = name
            tabIcon?.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
            window?.title = "\(name) - BingZip"
            tree?.showFileSystem(rootPath: url.path, selected: url.path)
        case .archive(let url, let inner):
            tabLabel?.stringValue = url.lastPathComponent
            tabIcon?.image = NSImage(systemSymbolName: "archivebox.fill", accessibilityDescription: nil)
            window?.title = "\(url.lastPathComponent) - BingZip"
            tree?.showArchive(name: url.lastPathComponent, key: url.path,
                              entries: leftPanel?.archiveEntries ?? [],
                              selectedInner: inner)
        }
    }

    /// 显示 / 隐藏左侧目录树
    func showTree(_ visible: Bool) {
        guard let tree = tree, let constraint = treeWidth else { return }
        tree.isHidden = !visible
        dividerView?.isHidden = !visible
        constraint.constant = visible ? 220 : 0
    }

    func setBusy(_ busy: Bool) {
        // Reserved for progress indication
    }

    /// 键盘焦点落到文件列表,方向键 / Return / 快捷键无需先点击列表。
    func focusInitialResponder() {
        window?.makeFirstResponder(leftPanel.tableView)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let w = window, let responder = w.firstResponder else { return }
        // 正在编辑路径 / 其它文本框时不要抢焦点
        if responder is NSTextView { return }
        if responder is NSTableView { return }
        w.makeFirstResponder(leftPanel.tableView)
    }

    func openArchiveDialog() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "选择要打开的压缩包"
        if panel.runModal() == .OK, let url = panel.url {
            activePanel.navigate(toFile: url)
        }
    }

    func addBookmark() {
        let dir = activePanel.currentDirectory
        var bookmarks = UserDefaults.standard.stringArray(forKey: "BingZipBookmarks") ?? []
        let path = dir.path
        if !bookmarks.contains(path) {
            bookmarks.append(path)
            UserDefaults.standard.set(bookmarks, forKey: "BingZipBookmarks")
        }
        if let delegate = NSApp.delegate as? AppDelegate {
            NSApp.mainMenu = delegate.buildMenu()
        }
        leftPanel.refreshSidebar()
        rightPanel.refreshSidebar()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        (NSApp.delegate as? AppDelegate)?.removeWindow(self)
        return true
    }
}

// MARK: - Toolbar actions
extension MainWindowController {

    @objc func openAction() { openArchiveDialog() }

    @objc func newArchiveAction() { activePanel.doNewEmptyFile() }

    @objc func extractAction() { activePanel.doExtract() }

    @objc func deleteAction() { activePanel.doDelete() }

    /// “测试”同时承担扫描:
    /// - 已进入压缩包或选中压缩包 → 测试该压缩包
    /// - 普通文件夹中未选中压缩包 → 扫描当前文件夹(含子目录)的所有压缩包
    @objc func testAction() {
        if hasTestableArchive {
            activePanel.doTest()
        } else {
            activePanel.doScanArchives()
        }
    }

    private var hasTestableArchive: Bool {
        if activePanel.currentArchiveURL != nil { return true }
        return activePanel.selectedItems().contains { item in
            guard !item.isDirectory, let url = item.fileURL else { return false }
            return isKnownArchive(url)
        }
    }

    @objc func codePageAction() { showCodePageDialog() }

    // 旧菜单仍在使用的动作
    @objc func addAction() { activePanel.doAdd() }
    @objc func copyAction() { activePanel.doCopy() }
    @objc func pasteAction() { activePanel.doPaste() }
    @objc func moveAction() { activePanel.doMove() }
    @objc func propertiesAction() { activePanel.doProperties() }
    @objc func newFolderAction() { activePanel.doNewFolder() }

    /// 代码页选择(用于解析压缩包内非 Unicode 文件名)
    func showCodePageDialog() {
        let options = CodePage.options
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26), pullsDown: false)
        popup.addItems(withTitles: options.map { $0.title })
        popup.selectItem(at: CodePage.currentIndex)

        let alert = NSAlert()
        alert.messageText = "代码页"
        alert.informativeText = "创建 Zip 压缩包时用于文件名编码(旧版 Windows 解压兼容):"
        alert.accessoryView = popup
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let index = max(0, min(popup.indexOfSelectedItem, options.count - 1))
        CodePage.set(value: options[index].value)
    }
}
