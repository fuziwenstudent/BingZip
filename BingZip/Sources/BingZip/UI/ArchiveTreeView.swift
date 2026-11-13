import AppKit

/// 目录树节点:文件系统模式保存绝对路径,压缩包模式保存包内相对路径。
final class TreeNode {
    let title: String
    let path: String
    let isDirectory: Bool
    let symbol: String
    var children: [TreeNode] = []
    var loaded = false
    var isArchiveRoot = false

    init(title: String, path: String, isDirectory: Bool, symbol: String) {
        self.title = title
        self.path = path
        self.isDirectory = isDirectory
        self.symbol = symbol
    }
}

/// Bandizip 风格左侧目录树:
/// - 文件系统模式:常用位置 + 磁盘目录(按需加载)
/// - 压缩包模式:压缩包内文件夹层级
final class ArchiveTreeView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {

    var onSelectPath: ((String) -> Void)?
    var onSelectInnerPath: ((String) -> Void)?
    /// 双指滑动与文件列表保持一致:右滑后退、左滑前进
    var onSwipeBack: (() -> Void)?
    var onSwipeForward: (() -> Void)?

    private var outline: NSOutlineView!
    private var scroll: TrackpadScrollView!
    private var roots: [TreeNode] = []

    private enum Mode { case fileSystem, archive }
    private var mode: Mode = .fileSystem
    private var suppressSelection = false
    private var archiveKey = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
        showFileSystem(rootPath: NSHomeDirectory(), selected: NSHomeDirectory())
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        outline = NSOutlineView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tree"))
        col.title = ""
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.headerView = nil
        outline.rowHeight = 22
        outline.indentationPerLevel = 14
        outline.dataSource = self
        outline.delegate = self
        outline.selectionHighlightStyle = .sourceList
        outline.backgroundColor = .clear
        outline.autoresizesOutlineColumn = true
        outline.allowsEmptySelection = true
        if #available(macOS 11.0, *) { outline.style = .sourceList }

        scroll = TrackpadScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.onSwipeRight = { [weak self] in self?.onSwipeBack?() }
        scroll.onSwipeLeft = { [weak self] in self?.onSwipeForward?() }
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemWillExpand(_:)),
            name: NSOutlineView.itemWillExpandNotification,
            object: outline)
    }

    /// 展开前加载子目录,避免在布局/数据源回调中同步读盘导致重排死循环
    @objc private func itemWillExpand(_ note: Notification) {
        guard let node = note.userInfo?["NSObject"] as? TreeNode else { return }
        if mode == .fileSystem {
            _ = fileSystemChildren(node)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    /// 切换到文件系统模式并高亮当前路径(尽力而为)。
    func showFileSystem(rootPath: String, selected: String) {
        mode = .fileSystem
        archiveKey = ""
        let home = NSHomeDirectory()
        var nodes: [TreeNode] = []
        func add(_ title: String, _ symbol: String, _ path: String) {
            guard FileManager.default.fileExists(atPath: path) else { return }
            nodes.append(TreeNode(title: title, path: path, isDirectory: true, symbol: symbol))
        }
        add("主目录", "house", home)
        add("桌面", "desktopcomputer", home + "/Desktop")
        add("下载", "arrow.down.circle", home + "/Downloads")
        add("文稿", "doc.text", home + "/Documents")
        add("应用程序", "square.grid.2x2", "/Applications")
        add("宗卷", "externaldrive", "/Volumes")
        add("电脑", "internaldrive", "/")
        roots = nodes
        outline.reloadData()
        // 只展开"主目录":展开桌面/文稿/下载会触发 macOS 隐私授权弹窗
        if let homeRoot = roots.first { outline.expandItem(homeRoot) }
        selectFileSystemPath(selected)
    }

    /// 切换到压缩包模式并高亮包内路径。
    func showArchive(name: String, key: String, entries: [ArchiveEntry], selectedInner: String) {
        if mode == .archive, archiveKey == key {
            selectArchivePath(selectedInner)
            return
        }
        mode = .archive
        archiveKey = key

        let root = TreeNode(title: name, path: "", isDirectory: true, symbol: "archivebox.fill")
        root.isArchiveRoot = true
        root.loaded = true

        var index: [String: TreeNode] = ["": root]
        let dirPaths = entries
            .filter { $0.isDirectory }
            .map { $0.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { !$0.isEmpty }
            .sorted { $0.count < $1.count }

        for p in dirPaths {
            var parent = root
            var acc: [String] = []
            for comp in p.split(separator: "/").map(String.init) {
                acc.append(comp)
                let full = acc.joined(separator: "/")
                if let existing = index[full] {
                    parent = existing
                    continue
                }
                let node = TreeNode(title: comp, path: full, isDirectory: true, symbol: "folder")
                node.loaded = true
                parent.children.append(node)
                index[full] = node
                parent = node
            }
        }

        roots = [root]
        outline.reloadData()
        outline.expandItem(root, expandChildren: true)
        selectArchivePath(selectedInner)
    }

    // MARK: - Selection sync

    private func selectFileSystemPath(_ path: String) {
        suppressSelection = true
        defer { suppressSelection = false }
        guard let node = findNode(in: roots, matching: { $0.path == path }) else { return }
        reveal(node)
    }

    private func selectArchivePath(_ inner: String) {
        suppressSelection = true
        defer { suppressSelection = false }
        guard let root = roots.first else { return }
        if inner.isEmpty {
            let row = outline.row(forItem: root)
            if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            return
        }
        guard let node = findNode(in: roots, matching: { $0.path == inner }) else { return }
        reveal(node)
    }

    private func findNode(in nodes: [TreeNode], matching predicate: (TreeNode) -> Bool) -> TreeNode? {
        for n in nodes {
            if predicate(n) { return n }
            if n.loaded, let hit = findNode(in: n.children, matching: predicate) { return hit }
        }
        return nil
    }

    private func reveal(_ node: TreeNode) {
        if let chain = chainTo(node, in: roots) {
            for n in chain.dropLast() { outline.expandItem(n) }
        }
        let row = outline.row(forItem: node)
        if row >= 0 {
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outline.scrollRowToVisible(row)
        }
    }

    private func chainTo(_ target: TreeNode, in nodes: [TreeNode]) -> [TreeNode]? {
        for n in nodes {
            if n === target { return [n] }
            if n.loaded, let sub = chainTo(target, in: n.children) { return [n] + sub }
        }
        return nil
    }

    // MARK: - Lazy loading

    private func fileSystemChildren(_ node: TreeNode) -> [TreeNode] {
        if node.loaded { return node.children }
        node.loaded = true
        var out: [TreeNode] = []
        let fm = FileManager.default
        if let urls = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: node.path),
                                                 includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles]) {
            let sorted = urls.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            for u in sorted {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                    out.append(TreeNode(title: u.lastPathComponent,
                                        path: u.path,
                                        isDirectory: true,
                                        symbol: "folder"))
                }
            }
        }
        node.children = out
        return out
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? TreeNode else { return roots.count }
        if mode == .archive { return node.children.count }
        // 子项在 itemWillExpand 中加载,这里只返回已加载结果
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? TreeNode else { return roots[index] }
        if mode == .archive { return node.children[index] }
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? TreeNode else { return false }
        if mode == .archive { return !node.children.isEmpty }
        // 文件系统节点都是目录,一律可展开(无子目录时展开后自然为空)
        return true
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? TreeNode else { return nil }
        let cell = NSTableCellView()

        let iv = NSImageView()
        iv.image = NSImage(systemSymbolName: node.symbol, accessibilityDescription: nil)
        iv.contentTintColor = node.isArchiveRoot ? .controlAccentColor : .secondaryLabelColor
        iv.translatesAutoresizingMaskIntoConstraints = false

        let tf = NSTextField(labelWithString: node.title)
        tf.font = .systemFont(ofSize: 12)
        tf.lineBreakMode = .byTruncatingMiddle
        tf.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(iv)
        cell.addSubview(tf)
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 16),
            iv.heightAnchor.constraint(equalToConstant: 16),
            tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 6),
            tf.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelection else { return }
        let row = outline.selectedRow
        guard row >= 0, let node = outline.item(atRow: row) as? TreeNode else { return }
        if mode == .archive {
            onSelectInnerPath?(node.path)
        } else {
            onSelectPath?(node.path)
        }
    }
}
