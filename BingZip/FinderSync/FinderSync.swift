import Cocoa
import FinderSync

/// Finder Sync extension: adds top-level items to Finder's context menu:
///   • 压缩到压缩包  → 只打开压缩对话框
///   • 解压到…       → 只打开解压对话框
///   • 打开压缩包    → 在 BingZip 主界面中浏览压缩包
/// The extension only forwards the selected paths to the main app through the
/// `bingzip://` URL scheme; all file access happens in the unsandboxed app.
final class FinderSync: FIFinderSync {

    private static let archiveExtensions: Set<String> = [
        "7z", "zip", "rar", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz",
        "lzma", "cab", "wim", "swm", "iso", "udf", "chm", "msi", "jar", "xar",
        "dmg", "hfs", "z", "taz", "lzh", "lha", "arj", "rpm", "deb", "cramfs",
        "squashfs", "lz4", "lz5", "sfs", "fat", "ntfs", "vhd", "appx",
    ]

    override init() {
        super.init()
        // Activate in every Finder folder, including mounted volumes.
        var roots: Set<URL> = [URL(fileURLWithPath: "/")]
        if let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]) {
            roots.formUnion(volumes)
        }
        FIFinderSyncController.default().directoryURLs = roots
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        // Only the two Finder context menus; no toolbar / sidebar menus.
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else {
            return nil
        }
        let urls = selection(for: menuKind)
        guard !urls.isEmpty else { return nil }

        let menu = NSMenu(title: "")

        let compress = NSMenuItem(title: "压缩到压缩包",
                                  action: #selector(compressSelected(_:)),
                                  keyEquivalent: "")
        compress.target = self
        compress.image = NSImage(systemSymbolName: "archivebox",
                                 accessibilityDescription: "压缩到压缩包")
        menu.addItem(compress)

        // “解压到…” directly opens the extract dialog. Only shown for a single
        // archive so the destination settings stay unambiguous.
        if urls.count == 1, Self.isArchive(urls[0]) {
            let extract = NSMenuItem(title: "解压到…",
                                     action: #selector(extractSelected(_:)),
                                     keyEquivalent: "")
            extract.target = self
            extract.image = NSImage(systemSymbolName: "square.and.arrow.down",
                                    accessibilityDescription: "解压到…")
            menu.addItem(extract)
        }

        // Only offer "打开压缩包" when at least one selected item is an archive.
        if urls.contains(where: Self.isArchive) {
            let open = NSMenuItem(title: "打开压缩包",
                                  action: #selector(openSelected(_:)),
                                  keyEquivalent: "")
            open.target = self
            open.image = NSImage(systemSymbolName: "doc.zipper",
                                 accessibilityDescription: "打开压缩包")
            menu.addItem(open)
        }
        return menu
    }

    // MARK: - Actions

    @objc private func compressSelected(_ sender: Any?) {
        let urls = selection()
        guard !urls.isEmpty else { return }
        forward(action: "compress", urls: urls)
    }

    @objc private func extractSelected(_ sender: Any?) {
        let archives = selection().filter(Self.isArchive)
        guard let first = archives.first else { return }
        forward(action: "extract", urls: [first])
    }

    @objc private func openSelected(_ sender: Any?) {
        let archives = selection().filter(Self.isArchive)
        guard !archives.isEmpty else { return }
        forward(action: "open", urls: archives)
    }

    // MARK: - Helpers

    private func selection(for menuKind: FIMenuKind? = nil) -> [URL] {
        let controller = FIFinderSyncController.default()
        if let menuKind = menuKind, menuKind == .contextualMenuForContainer,
           let target = controller.targetedURL() {
            return [target]
        }
        if let selected = controller.selectedItemURLs(), !selected.isEmpty {
            return selected
        }
        if let target = controller.targetedURL() {
            return [target]
        }
        return []
    }

    private func forward(action: String, urls: [URL]) {
        var components = URLComponents()
        components.scheme = "bingzip"
        components.host = action
        components.queryItems = urls.map { URLQueryItem(name: "path", value: $0.path) }
        guard let url = components.url else {
            NSLog("BingZipFinder: failed to build command URL")
            return
        }
        NSLog("BingZipFinder: \(action) \(urls.count) item(s)")
        NSWorkspace.shared.open(url)
    }

    private static func isArchive(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tar.bz2")
            || name.hasSuffix(".tar.xz") {
            return true
        }
        return archiveExtensions.contains(url.pathExtension.lowercased())
    }
}
