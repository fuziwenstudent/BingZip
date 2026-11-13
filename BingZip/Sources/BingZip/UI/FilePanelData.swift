import AppKit

// MARK: - Table data source & delegate
extension FilePanel: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // Column identifiers are "c0" ... "c6"
        let raw = tableColumn?.identifier.rawValue ?? "c0"
        let colID = Int(raw.dropFirst()) ?? 0
        let item = items[row]
        let cell = NSTableCellView()
        let tf = NSTextField(labelWithString: "")
        tf.font = .systemFont(ofSize: 12)
        tf.lineBreakMode = .byTruncatingMiddle
        cell.textField = tf
        cell.addSubview(tf)
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4).isActive = true
        tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor).isActive = true

        let sortCol = SortColumn(rawValue: colID) ?? .name

        if sortCol == .name {
            // Bandizip 风格:图标 + 文件名
            let iv = NSImageView()
            let symbol = item.isParent ? "arrow.turn.up.left"
                : (item.isDirectory ? "folder.fill" : fileSymbol(for: item.name))
            iv.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            iv.contentTintColor = item.isDirectory ? .systemBlue : .secondaryLabelColor
            iv.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                iv.widthAnchor.constraint(equalToConstant: 16),
                iv.heightAnchor.constraint(equalToConstant: 16),
                tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 6),
            ])
        } else {
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4).isActive = true
        }

        switch sortCol {
        case .name:
            tf.stringValue = item.name
        case .size:
            tf.alignment = .right
            tf.stringValue = item.isDirectory ? "" : formatBytes(item.size)
        case .packedSize:
            tf.alignment = .right
            // 7-Zip only knows packed size for the first file of a solid block;
            // file-system entries have no packed size at all.
            tf.stringValue = (item.isDirectory || item.packedSize == 0) ? "" : formatBytes(item.packedSize)
        case .type:
            tf.stringValue = item.isDirectory ? "文件夹" : fileKindName(forName: item.name, isDirectory: false)
        case .modified:
            if let d = item.modified {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd HH:mm:ss"
                tf.stringValue = df.string(from: d)
            }
        case .crc:
            tf.stringValue = item.crc
        case .attributes:
            tf.stringValue = item.attributes
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let desc = tableView.sortDescriptors.first,
              let colID = Int(desc.key ?? ""),
              let col = SortColumn(rawValue: colID) else { return }
        sortColumn = col
        sortAscending = desc.ascending
        sortItems()
        tableView.reloadData()
    }
}

/// 按扩展名挑选列表图标(Bandizip 风格)
func fileSymbol(for name: String) -> String {
    switch (name as NSString).pathExtension.lowercased() {
    case "7z", "zip", "rar", "tar", "gz", "bz2", "xz", "tgz", "lzma", "cab", "iso", "wim":
        return "archivebox"
    case "png", "jpg", "jpeg", "gif", "bmp", "icns", "tiff", "webp", "heic":
        return "photo"
    case "mp4", "mov", "mkv", "avi", "flv", "mp3", "wav", "flac", "aac", "m4a":
        return "play.rectangle"
    case "pdf":
        return "doc.richtext"
    case "txt", "log", "md", "rtf":
        return "doc.text"
    case "swift", "c", "cpp", "h", "hpp", "m", "mm", "py", "js", "ts", "sh", "rb", "go", "java":
        return "chevron.left.forwardslash.chevron.right"
    case "app":
        return "app"
    case "dmg", "pkg":
        return "shippingbox"
    default:
        return "doc"
    }
}
