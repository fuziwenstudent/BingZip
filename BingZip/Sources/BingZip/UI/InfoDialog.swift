import AppKit

/// Properties dialog (7-Zip "Info" dialog).
final class InfoDialog: NSWindowController {

    private let panel: FilePanel

    init(panel: FilePanel) {
        self.panel = panel
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        w.contentMinSize = NSSize(width: 380, height: 300)
        w.title = "属性"
        super.init(window: w)
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func rows() -> [(String, String)] {
        var result: [(String, String)] = []
        let items = panel.selectedItems()
        if panel.isArchiveMode, let archive = panel.currentArchiveURL {
            result.append(("名称", archive.lastPathComponent))
            result.append(("位置", archive.deletingLastPathComponent().path))
            result.append(("类型", "压缩包 (\((archive.pathExtension as NSString).uppercased))"))
            let totalSize = panel.archiveEntries.filter { !$0.isDirectory }.reduce(Int64(0)) { $0 + $1.size }
            let fileCount = panel.archiveEntries.filter { !$0.isDirectory }.count
            let folderCount = panel.archiveEntries.filter { $0.isDirectory }.count
            result.append(("大小", formatBytes(totalSize)))
            result.append(("文件", "\(fileCount) 个文件, \(folderCount) 个文件夹"))
            let encryptedCount = panel.archiveEntries.filter { $0.encrypted }.count
            if encryptedCount > 0 { result.append(("加密", "\(encryptedCount) 个加密条目")) }
            let selected = items
            if selected.count == 1, let s = selected.first {
                result.append(("-- 选中项目", s.name))
                if !s.isDirectory { result.append(("大小", formatBytes(s.size))) }
                if !s.crc.isEmpty { result.append(("CRC", s.crc)) }
                if let m = s.modified {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    result.append(("修改时间", df.string(from: m)))
                }
            }
        } else if !items.isEmpty {
            if items.count == 1, let item = items.first, let url = item.fileURL {
                result.append(("名称", item.name))
                result.append(("位置", url.deletingLastPathComponent().path))
                result.append(("类型", item.isDirectory ? "文件夹" : fileKindName(forName: item.name, isDirectory: false)))
                result.append(("大小", item.isDirectory ? "--" : formatBytes(item.size)))
                if let m = item.modified {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    result.append(("修改时间", df.string(from: m)))
                }
            } else {
                result.append(("选中项目", "\(items.count) 个"))
                let total = items.reduce(Int64(0)) { $0 + $1.size }
                result.append(("总大小", formatBytes(total)))
            }
        } else if case .folder(let url) = panel.location {
            result.append(("位置", url.path))
            let count = panel.items.filter { !$0.isParent }.count
            result.append(("项目数", "\(count)"))
        }
        return result
    }

    private func buildContent() {
        guard let cv = window?.contentView else { return }
        let data = rows()
        let sv = NSStackView()
        sv.orientation = .vertical
        sv.alignment = .leading
        sv.spacing = 4
        sv.translatesAutoresizingMaskIntoConstraints = false
        for (k, v) in data {
            let kv = NSStackView()
            kv.orientation = .horizontal
            kv.spacing = 8
            let label = NSTextField(labelWithString: k + ":")
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.setContentHuggingPriority(.required, for: .horizontal)
            let value = NSTextField(labelWithString: v)
            value.font = .systemFont(ofSize: 12)
            value.lineBreakMode = .byTruncatingMiddle
            kv.addArrangedSubview(label)
            kv.addArrangedSubview(value)
            sv.addArrangedSubview(kv)
        }
        let ok = NSButton(title: "确定", target: self, action: #selector(closeWindow))
        ok.keyEquivalent = "\r"
        ok.bezelStyle = .rounded
        sv.addArrangedSubview(ok)
        cv.addSubview(sv)
        NSLayoutConstraint.activate([
            sv.topAnchor.constraint(equalTo: cv.topAnchor, constant: 14),
            sv.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            sv.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            sv.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor, constant: -12),
        ])
    }

    @objc func closeWindow() {
        window?.orderOut(nil)
        NSApp.stopModal()
    }

    func runModal(on parent: NSWindow?) {
        guard let w = window else { return }
        w.center()
        NSApp.runModal(for: w)
    }
}