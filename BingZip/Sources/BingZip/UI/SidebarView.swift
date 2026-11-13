import AppKit

/// Sidebar with common macOS folders, volumes and user bookmarks.
final class SidebarView: NSView, NSTableViewDataSource, NSTableViewDelegate {

    struct Place {
        let title: String
        let symbol: String
        let path: String
    }

    var onSelect: ((String) -> Void)?

    private var tableView: NSTableView!
    private var scroll: NSScrollView!
    private var items: [(place: Place, isHeader: Bool)] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        tableView = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("place"))
        col.title = "位置"
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .regular

        scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 150),
        ])
    }

    func reload() {
        let home = NSHomeDirectory()
        var places: [Place] = [
            Place(title: "主目录", symbol: "house", path: home),
            Place(title: "桌面", symbol: "desktopcomputer", path: home + "/Desktop"),
            Place(title: "下载", symbol: "arrow.down.circle", path: home + "/Downloads"),
            Place(title: "文稿", symbol: "doc.text", path: home + "/Documents"),
            Place(title: "图片", symbol: "photo", path: home + "/Pictures"),
            Place(title: "音乐", symbol: "music.note", path: home + "/Music"),
            Place(title: "影片", symbol: "film", path: home + "/Movies"),
            Place(title: "应用程序", symbol: "square.grid.2x2", path: "/Applications"),
            Place(title: "iCloud Drive", symbol: "icloud",
                  path: home + "/Library/Mobile Documents/com~apple~CloudDocs"),
            Place(title: "宗卷", symbol: "externaldrive", path: "/Volumes"),
            Place(title: "根目录", symbol: "internaldrive", path: "/"),
        ]
        places = places.filter { FileManager.default.fileExists(atPath: $0.path) }

        var rows: [(Place, Bool)] = places.map { ($0, false) }
        let bookmarks = UserDefaults.standard.stringArray(forKey: "BingZipBookmarks") ?? []
        if !bookmarks.isEmpty {
            rows.append((Place(title: "收藏夹", symbol: "", path: ""), true))
            for b in bookmarks {
                let name = (b as NSString).lastPathComponent
                rows.append((Place(title: name.isEmpty ? b : name, symbol: "folder", path: b), false))
            }
        }
        items = rows
        tableView.reloadData()
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let (place, isHeader) = items[row]
        let cell = NSTableCellView()

        if isHeader {
            let tf = NSTextField(labelWithString: place.title.uppercased())
            tf.font = .systemFont(ofSize: 10, weight: .semibold)
            tf.textColor = .secondaryLabelColor
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf)
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        let iv = NSImageView()
        iv.image = NSImage(systemSymbolName: place.symbol, accessibilityDescription: nil)
        iv.contentTintColor = .controlAccentColor
        iv.translatesAutoresizingMaskIntoConstraints = false
        let tf = NSTextField(labelWithString: place.title)
        tf.font = .systemFont(ofSize: 12)
        tf.lineBreakMode = .byTruncatingMiddle
        tf.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(iv)
        cell.addSubview(tf)
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 16),
            iv.heightAnchor.constraint(equalToConstant: 16),
            tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 6),
            tf.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return !items[row].isHeader
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        let (place, isHeader) = items[row]
        guard !isHeader, !place.path.isEmpty else { return }
        onSelect?(place.path)
    }
}