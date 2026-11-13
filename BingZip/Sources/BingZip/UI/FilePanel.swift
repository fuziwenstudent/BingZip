import AppKit

struct PanelItem {
    var name: String
    var isDirectory: Bool
    var size: Int64
    var packedSize: Int64
    var modified: Date?
    var crc: String
    var attributes: String
    var fileURL: URL?      // set for file-system entries
    var archivePath: String? // full path inside archive
    var isParent = false   // ".." entry
}

enum PanelLocation: Equatable {
    case folder(URL)
    case archive(url: URL, innerPath: String)
}

final class FilePanel: NSView {

    // MARK: - State

    private(set) var location: PanelLocation = .folder(URL(fileURLWithPath: NSHomeDirectory()))
    private(set) var items: [PanelItem] = []
    private(set) var archiveEntries: [ArchiveEntry] = []
    private(set) var archivePassword = ""

    var sortColumn: SortColumn = .name
    var sortAscending = true

    var pathBar: PathBarView!
    var tableView: NSTableView!
    var statusField: NSTextField!
    var sidebar: SidebarView!

    /// 位置变化回调(供主窗口同步标题 / 目录树)
    var onLocationChange: ((PanelLocation) -> Void)?

    /// 名称筛选关键字
    var filterText = "" {
        didSet { reload() }
    }

    /// 进行中的任务进度窗口(强引用,防止提前释放)
    var taskWindows: [ProgressWindowController] = []

    private var scrollLeadingToSidebar: NSLayoutConstraint!
    private var scrollLeadingToView: NSLayoutConstraint!
    private var userWantsSidebar = true
    private var autoCollapsed = false

    private var backStack: [PanelLocation] = []
    private var forwardStack: [PanelLocation] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        navigate(toFile: URL(fileURLWithPath: NSHomeDirectory()))
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI setup

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        registerForDraggedTypes([.fileURL])

        pathBar = PathBarView()
        pathBar.onUp = { [weak self] in self?.navigateUp() }
        pathBar.onBack = { [weak self] in self?.goBack() }
        pathBar.onForward = { [weak self] in self?.goForward() }
        pathBar.onNavigate = { [weak self] url in self?.navigate(toFile: url) }
        pathBar.onNavigateArchive = { [weak self] url, inner in
            if case .archive(let currentURL, _) = self?.location, currentURL == url {
                self?.pushHistory()
                self?.setLocation(.archive(url: url, innerPath: inner))
                self?.reload()
            } else {
                self?.navigateToArchive(url, innerPath: inner)
            }
        }
        pathBar.onPickLocation = { [weak self] path in
            self?.navigate(toFile: URL(fileURLWithPath: path))
        }
        pathBar.onToggleSidebar = { [weak self] in
            self?.toggleSidebar()
        }

        let fileTable = FileTableView()
        fileTable.panel = self
        tableView = fileTable
        // Bandizip 列顺序: 名称 / 压缩后大小 / 原始大小 / 类型(c 编号沿用 SortColumn 原始值)
        let colDefs: [(String, String, CGFloat)] = [
            ("名称", "c0", 320), ("压缩后大小", "c2", 110), ("原始大小", "c1", 110), ("类型", "c3", 130),
            ("修改时间", "c4", 150), ("CRC", "c5", 90), ("属性", "c6", 90)
        ]
        for (i, c) in colDefs.enumerated() {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(c.1))
            col.title = c.0
            col.width = c.2
            col.minWidth = i == 0 ? 160 : 70
            col.sortDescriptorPrototype = NSSortDescriptor(key: String(c.1.dropFirst()), ascending: true)
            if i >= 4 { col.isHidden = true }   // 默认只显示 Bandizip 的四列
            tableView.addTableColumn(col)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        if #available(macOS 11.0, *) { tableView.style = .fullWidth }
        tableView.doubleAction = #selector(doubleClick(_:))
        tableView.target = self
        tableView.allowsMultipleSelection = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.menu = buildContextMenu()
        let scroll = TrackpadScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.borderType = .bezelBorder
        // Finder 风格:双指向右滑 = 后退,向左滑 = 前进
        scroll.onSwipeRight = { [weak self] in self?.goBack() }
        scroll.onSwipeLeft = { [weak self] in self?.goForward() }

        statusField = NSTextField(labelWithString: "")
        statusField.font = .systemFont(ofSize: 11)
        statusField.translatesAutoresizingMaskIntoConstraints = false

        sidebar = SidebarView()
        sidebar.onSelect = { [weak self] path in
            self?.navigate(toFile: URL(fileURLWithPath: path))
        }

        addSubview(pathBar)
        addSubview(sidebar)
        addSubview(scroll)
        addSubview(statusField)

        scrollLeadingToSidebar = scroll.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 8)
        scrollLeadingToView = scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
        scrollLeadingToSidebar.isActive = true

        NSLayoutConstraint.activate([
            pathBar.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            pathBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            pathBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            sidebar.topAnchor.constraint(equalTo: pathBar.bottomAnchor, constant: 6),
            sidebar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            sidebar.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),

            scroll.topAnchor.constraint(equalTo: pathBar.bottomAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            statusField.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 4),
            statusField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            statusField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            statusField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        let showSidebar = UserDefaults.standard.object(forKey: "BingZipShowSidebar") as? Bool ?? true
        setSidebarVisible(showSidebar)
    }

    /// Show / hide the places sidebar (user preference).
    func setSidebarVisible(_ visible: Bool) {
        userWantsSidebar = visible
        applySidebarVisibility()
    }

    func toggleSidebar() {
        userWantsSidebar.toggle()
        UserDefaults.standard.set(userWantsSidebar, forKey: "BingZipShowSidebar")
        applySidebarVisibility()
    }

    /// Sidebar is visible only when the user wants it AND the panel is wide enough.
    private func applySidebarVisibility() {
        let visible = userWantsSidebar && !autoCollapsed
        sidebar.isHidden = !visible
        scrollLeadingToSidebar.isActive = false
        scrollLeadingToView.isActive = false
        if visible {
            scrollLeadingToSidebar.isActive = true
        } else {
            scrollLeadingToView.isActive = true
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        // Auto-collapse the sidebar when the panel becomes narrow
        let shouldAutoHide = bounds.width < 480
        if shouldAutoHide != autoCollapsed {
            autoCollapsed = shouldAutoHide
            applySidebarVisibility()
        }
    }

    func refreshSidebar() {
        sidebar.reload()
    }

    private func buildContextMenu() -> NSMenu {
        let m = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            m.addItem(i)
        }
        add("打开", #selector(doubleClick(_:)))
        add("添加…", #selector(doAdd))
        add("解压…", #selector(doExtract))
        add("测试", #selector(doTest))
        m.addItem(.separator())
        add("复制", #selector(doCopy))
        add("粘贴", #selector(doPaste))
        add("移动", #selector(doMove))
        add("删除", #selector(doDelete))
        add("重命名", #selector(doRename))
        m.addItem(.separator())
        add("属性…", #selector(doProperties))
        return m
    }

    // MARK: - Helpers

    var isArchiveMode: Bool {
        if case .archive = location { return true }
        return false
    }

    var currentArchiveURL: URL? {
        if case .archive(let url, _) = location { return url }
        return nil
    }

    private func setLocation(_ l: PanelLocation) {
        location = l
        pathBar.update(location: l,
                       canGoBack: !backStack.isEmpty,
                       canGoForward: !forwardStack.isEmpty)
        onLocationChange?(l)
    }

    /// 进入压缩包内的某个目录(供左侧目录树使用)
    func goToInnerPath(_ inner: String) {
        guard case .archive(let url, let current) = location else { return }
        let normalized = inner.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard normalized != current else { return }
        pushHistory()
        setLocation(.archive(url: url, innerPath: normalized))
        reload()
    }

    // MARK: - History

    private func pushHistory() {
        if backStack.last != location {
            backStack.append(location)
        }
        forwardStack.removeAll()
    }

    func goBack() {
        guard let prev = backStack.popLast() else { return }
        forwardStack.append(location)
        applyHistoryLocation(prev)
        pathBar.update(location: location,
                       canGoBack: !backStack.isEmpty,
                       canGoForward: !forwardStack.isEmpty)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(location)
        applyHistoryLocation(next)
        pathBar.update(location: location,
                       canGoBack: !backStack.isEmpty,
                       canGoForward: !forwardStack.isEmpty)
    }

    private func applyHistoryLocation(_ l: PanelLocation) {
        switch l {
        case .folder:
            setLocation(l)
            reload()
        case .archive(let url, let inner):
            if currentArchiveURL == url && !archiveEntries.isEmpty {
                setLocation(l)
                reload()
            } else {
                navigateToArchive(url, innerPath: inner, recordHistory: false)
            }
        }
    }

    // MARK: - Drag & Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self],
                                                   options: [.urlReadingFileURLsOnly: true]) {
            return .copy
        }
        return []
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }

        // A single archive dropped -> open it in this panel
        if urls.count == 1 {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: urls[0].path, isDirectory: &isDir)
            if exists, !isDir.boolValue, isKnownArchive(urls[0]) {
                navigateToArchive(urls[0])
                return true
            }
        }
        // Otherwise ask for compression settings (7-Zip style drag & drop)
        let dialog = AddDialog(sources: urls, suggestDirectory: currentDirectory)
        dialog.runModal(on: window) { [weak self] in
            self?.reload()
            self?.otherPanel?.reload()
        }
        return true
    }

    // MARK: - Navigation

    func navigate(toFile url: URL, recordHistory: Bool = true) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            if recordHistory { pushHistory() }
            setLocation(.folder(url))
            reload()
        } else if isKnownArchive(url) {
            navigateToArchive(url, recordHistory: recordHistory)
        }
    }

    func navigateToArchive(_ url: URL, password: String = "", innerPath: String = "",
                           recordHistory: Bool = true) {
        archivePassword = password
        let controller = self.window?.windowController as? MainWindowController
        controller?.setBusy(true)
        DispatchQueue.global().async {
            do {
                let listing = try SevenZip.shared.list(archive: url, password: password)
                DispatchQueue.main.async {
                    controller?.setBusy(false)
                    if listing.entries.isEmpty && password.isEmpty {
                        self.checkEmptyOrEncrypted(url: url)
                        return
                    }
                    if recordHistory { self.pushHistory() }
                    self.archiveEntries = listing.entries
                    self.setLocation(.archive(url: url, innerPath: innerPath))
                    self.reload()
                }
            } catch {
                DispatchQueue.main.async {
                    controller?.setBusy(false)
                    self.checkEmptyOrEncrypted(url: url)
                }
            }
        }
    }

    /// Empty archive -> show it; encrypted header -> ask for password.
    private func checkEmptyOrEncrypted(url: URL) {
        let probe = try? SevenZip.shared.run(["l", "-slt", "-ba", "-p", url.path])
        if let code = probe?.exitCode, code == 0 {
            self.archiveEntries = []
            self.setLocation(.archive(url: url, innerPath: ""))
            self.reload()
            return
        }
        let err = (probe?.stderr ?? "").lowercased()
        let needsPassword = err.contains("password") || err.contains("encrypted") || err.contains("cannot open")
        guard needsPassword else {
            navigate(toFile: url.deletingLastPathComponent())
            return
        }
        let d = TextInputDialog(title: "输入密码", prompt: "压缩包已加密,请输入密码:", defaultValue: "", secure: true)
        if let pw = d.runModal(on: window), !pw.isEmpty {
            navigateToArchive(url, password: pw)
        } else {
            navigate(toFile: url.deletingLastPathComponent())
        }
    }

    func navigateUp() {
        if case .archive(_, let inner) = location {
            if inner.isEmpty {
                let parent = (currentArchiveURL ?? URL(fileURLWithPath: "/")).deletingLastPathComponent()
                navigate(toFile: parent)
            } else {
                let parts = inner.split(separator: "/").map(String.init)
                let parent = parts.dropLast().joined(separator: "/")
                pushHistory()
                setLocation(.archive(url: currentArchiveURL!, innerPath: parent))
                reload()
            }
            return
        }
        if case .folder(let url) = location, url.path != "/" {
            navigate(toFile: url.deletingLastPathComponent())
        }
    }

    func navigateInto(item: PanelItem) {
        if item.isParent { navigateUp(); return }
        if item.isDirectory {
            if let url = item.fileURL {
                navigate(toFile: url)
            } else if case .archive(let url, let inner) = location {
                let newInner = inner.isEmpty ? item.name : inner + "/" + item.name
                pushHistory()
                setLocation(.archive(url: url, innerPath: newInner))
                reload()
            }
            return
        }
        // File
        if let url = item.fileURL {
            if isKnownArchive(url) {
                navigateToArchive(url)
            } else {
                NSWorkspace.shared.open(url)
            }
        } else if case .archive(let url, _) = location {
            // Open file from archive: extract it (and children) to temp then open
            extractAndOpen(item: item, archive: url)
        }
    }

    @objc func doubleClick(_ sender: Any?) {
        openSelected()
    }

    /// 打开当前选中的项目(供 Return / ⌘↓ 与双击使用)
    func openSelected() {
        guard let item = selectedItem() else { return }
        navigateInto(item: item)
    }

    /// 让文件列表取得键盘焦点(启动与从 Dock 恢复窗口时使用)
    func focusTable() {
        window?.makeFirstResponder(tableView)
    }

    // MARK: - Selection

    func selectedItem() -> PanelItem? {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return nil }
        return items[row]
    }

    func selectedItems() -> [PanelItem] {
        let rows = tableView.selectedRowIndexes
        guard rows.count > 0 else { return [] }
        var r: [PanelItem] = []
        for i in rows where i < items.count { r.append(items[i]) }
        if r.isEmpty, let s = selectedItem() { r = [s] }
        return r.filter { !$0.isParent }
    }

    @objc func doSelectAll() { tableView.selectAll(nil) }

    @objc func doInvertSelection() {
        let total = tableView.numberOfRows
        for i in 0..<total {
            if tableView.isRowSelected(i) { tableView.deselectRow(i) }
            else { tableView.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: true) }
        }
    }

    // MARK: - Reload

    func doRefresh() { reload() }

    func reload() {
        switch location {
        case .folder(let url):
            items = Self.loadDirectory(url)
        case .archive(_, let inner):
            items = Self.children(of: inner, in: archiveEntries)
        }
        if !filterText.isEmpty {
            items = items.filter { $0.isParent || $0.name.localizedCaseInsensitiveContains(filterText) }
        }
        sortItems()
        tableView.reloadData()
        let count = items.filter { !$0.isParent }.count
        let totalSize = items.filter { !$0.isParent && !$0.isDirectory }.reduce(Int64(0)) { $0 + $1.size }
        statusField.stringValue = "\(count) 个对象  \(formatBytes(totalSize))" +
            (filterText.isEmpty ? "" : "  (筛选: \(filterText))")
    }

    func sortItems() {
        let parent = items.filter { $0.isParent }
        let rest = items.filter { !$0.isParent }
        let sorted = rest.sorted { a, b in
            var result = false
            switch sortColumn {
            case .name: result = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .size: result = a.size < b.size
            case .packedSize: result = a.packedSize < b.packedSize
            case .type: result = a.isDirectory == b.isDirectory
                ? fileKindName(forName: a.name, isDirectory: a.isDirectory) < fileKindName(forName: b.name, isDirectory: b.isDirectory)
                : b.isDirectory
            case .modified:
                let da = a.modified ?? Date.distantPast, db = b.modified ?? Date.distantPast
                result = da < db
            case .crc: result = a.crc < b.crc
            case .attributes: result = a.attributes < b.attributes
            }
            if a.isDirectory != b.isDirectory, sortColumn == .name { return a.isDirectory }
            return sortAscending ? result : !result
        }
        items = parent + sorted
    }
}