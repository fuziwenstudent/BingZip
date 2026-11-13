import AppKit

/// Clipboard for inter-panel copy/move
enum PanelClipboard {
    static var sources: [URL] = []
    static var fromArchive: (url: URL, entries: [String])? = nil
    static var isMove = false

    static func clear() {
        sources = []
        fromArchive = nil
        isMove = false
    }
}

// MARK: - Panel actions
extension FilePanel {

    var currentDirectory: URL {
        switch location {
        case .folder(let url): return url
        case .archive(let url, _): return url.deletingLastPathComponent()
        }
    }

    // MARK: Add (compress)

    @objc func doAdd() {
        let sel = selectedItems()
        let sources: [URL]
        if !sel.isEmpty {
            if isArchiveMode {
                sources = [currentArchiveURL].compactMap { $0 }
            } else {
                sources = sel.compactMap { $0.fileURL }
            }
        } else {
            if isArchiveMode, let a = currentArchiveURL {
                sources = [a]
            } else {
                if case .folder(let url) = location { sources = [url] } else { sources = [] }
            }
        }
        guard !sources.isEmpty else { return }
        let dialog = AddDialog(sources: sources, suggestDirectory: currentDirectory)
        dialog.runModal(on: window) { [weak self] in
            self?.reload()
            self?.otherPanel?.reload()
        }
    }

    /// 工具栏"添加":在压缩包内时向当前压缩包追加文件,否则打开新建对话框
    @objc func doAddFilesToArchive() {
        if isArchiveMode, let archive = currentArchiveURL {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.message = "选择要添加到 \(archive.lastPathComponent) 的文件"
            guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
            var args = ["a", "-y", "-bsp1", archive.path]
            if !archivePassword.isEmpty { args.append("-p\(archivePassword)") }
            args.append(contentsOf: panel.urls.map { $0.path })
            OperationRunner.shared.start(args: args,
                                         title: "添加到: \(archive.lastPathComponent)",
                                         window: window) { [weak self] ok, msg in
                if !ok {
                    let a = NSAlert(); a.messageText = "添加失败"; a.informativeText = msg; a.runModal()
                }
                if let self = self {
                    self.navigateToArchive(archive, password: self.archivePassword)
                }
            }
            return
        }
        doAdd()
    }

    // MARK: Extract

    @objc func doExtract() {
        let sel = selectedItems()
        if isArchiveMode, let archive = currentArchiveURL {
            let files: [String]? = {
                let chosen = sel.filter { !$0.isParent }
                if chosen.isEmpty { return nil }
                let currentInner: String = { if case .archive(_, let i) = location { return i }; return "" }()
                return chosen.map { item -> String in
                    if let p = item.archivePath { return p }
                    return currentInner.isEmpty ? item.name : currentInner + "/" + item.name
                }
            }()
            let dialog = ExtractDialog(archive: archive, files: files, suggestDirectory: currentDirectory)
            dialog.runModal(on: window) { [weak self] in
                self?.otherPanel?.reload()
            }
            return
        }
        let archives = sel.filter { !$0.isDirectory }.compactMap { $0.fileURL }.filter { isKnownArchive($0) }
        guard let first = archives.first else {
            let alert = NSAlert()
            alert.messageText = "没有选中压缩包"
            alert.informativeText = "请先选中一个或多个压缩文件,或进入压缩包后再解压。"
            alert.runModal()
            return
        }
        let dialog = ExtractDialog(archive: first, files: nil, suggestDirectory: currentDirectory)
        dialog.runModal(on: window) { [weak self] in
            self?.reload()
        }
    }

    // MARK: Test

    @objc func doTest() {
        // 优先测试当前打开的压缩包;否则要求先选中一个压缩包
        var archive: URL? = currentArchiveURL
        if archive == nil {
            let picked = selectedItems()
            if picked.count == 1, let u = picked[0].fileURL, isKnownArchive(u) {
                archive = u
            } else if let first = picked.compactMap({ $0.fileURL }).first(where: { isKnownArchive($0) }) {
                archive = first
            }
        }
        guard let a = archive else {
            let alert = NSAlert()
            alert.messageText = "请先选择一个压缩包"
            alert.informativeText = "在文件列表里点选一个压缩包,然后再点“测试”。"
            alert.addButton(withTitle: "知道了")
            alert.runModal()
            return
        }

        let pc = ProgressWindowController(title: "测试: \(a.lastPathComponent)")
        taskWindows.append(pc)
        pc.showWindow(nil)
        pc.window?.center()
        let start = Date()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = FilePanel.checkArchive(a) { line in
                DispatchQueue.main.async {
                    pc.updateProgress(line: line, elapsed: Date().timeIntervalSince(start))
                }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.taskWindows.removeAll { $0 === pc }
                pc.finish(success: true, message: "")
                pc.window?.orderOut(nil)
                self.showTestResult(result, url: a)
                self.reload()
            }
        }
    }

    /// 检查单个压缩包是否完好(注意:7zz 对“有警告”的包仍返回 0,需要看输出文本)
    static func checkArchive(_ url: URL, onLine: ((String) -> Void)? = nil) -> ArchiveCheckResult {
        guard let r = try? SevenZip.shared.run(["t", "-y", "-bsp1", "-p", url.path], onLine: onLine) else {
            return .damaged("无法读取这个文件")
        }
        let out = (r.stdout + "\n" + r.stderr).lowercased()
        if out.contains("password") || out.contains("encrypted") || out.contains("encrypt") {
            return .needsPassword
        }
        if r.exitCode == 0 && !out.contains("warning") && !out.contains("error") {
            return .ok
        }
        let detail = (r.stderr.isEmpty ? r.stdout : r.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .damaged(String(detail.prefix(600)))
    }

    private func showTestResult(_ result: ArchiveCheckResult, url: URL) {
        let alert = NSAlert()
        switch result {
        case .ok:
            alert.messageText = "压缩包完好"
            alert.informativeText = "“\(url.lastPathComponent)”没有发现问题。"
        case .needsPassword:
            alert.messageText = "压缩包已加密"
            alert.informativeText = "需要密码才能检查“\(url.lastPathComponent)”。"
        case .damaged(let msg):
            alert.messageText = "压缩包可能已损坏"
            alert.informativeText = msg.isEmpty ? "无法读取这个压缩包。" : msg
        }
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    var otherPanel: FilePanel? {
        guard let controller = window?.windowController as? MainWindowController else { return nil }
        return controller.leftPanel === self ? controller.rightPanel : controller.leftPanel
    }

    // MARK: File management

    @objc func doNewFolder() {
        guard case .folder(let dir) = location else { return }
        let d = TextInputDialog(title: "新建文件夹", prompt: "文件夹名称:", defaultValue: "新建文件夹")
        guard let name = d.runModal(on: window), !name.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(name), withIntermediateDirectories: true)
            reload()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// “新建”工具栏动作:创建空白文件
    @objc func doNewEmptyFile() {
        guard case .folder(let dir) = location else {
            let alert = NSAlert()
            alert.messageText = "请在文件夹里新建文件"
            alert.informativeText = "压缩包内部暂不支持直接新建文件。"
            alert.addButton(withTitle: "知道了")
            alert.runModal()
            return
        }
        let dialog = NewFileDialog()
        guard let name = dialog.runModal(on: window), !name.isEmpty else { return }
        let url = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            let alert = NSAlert()
            alert.messageText = "同名文件已存在"
            alert.informativeText = "请换一个名称。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            return
        }
        do {
            try Data().write(to: url)
            reload()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc func doDelete() {
        let sel = selectedItems()
        guard !sel.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "请先选择要删除的文件"
            alert.informativeText = "在文件列表里点选文件(可多选),然后再点“删除”。"
            alert.addButton(withTitle: "知道了")
            alert.runModal()
            return
        }
        if isArchiveMode, let archive = currentArchiveURL {
            let paths = sel.compactMap { $0.archivePath }
            guard !paths.isEmpty else { return }
            let alert = NSAlert()
            alert.messageText = "删除压缩包内的 \(paths.count) 个项目?"
            alert.addButton(withTitle: "删除")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            var args = ["d", "-y", "-bsp1", archive.path]
            args.append(contentsOf: paths)
            OperationRunner.shared.start(args: args, title: "从压缩包删除", window: window) { [weak self] ok, msg in
                if !ok {
                    let a = NSAlert(); a.messageText = "删除失败"; a.informativeText = msg; a.runModal()
                }
                self?.navigateToArchive(archive, password: self?.archivePassword ?? "")
            }
            return
        }
        let urls = sel.compactMap { $0.fileURL }
        guard !urls.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "将 \(urls.count) 个项目移到废纸篓?"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var failed = 0
        for url in urls {
            do {
                var resultingURL: NSURL? = nil
                try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            } catch { failed += 1 }
        }
        if failed > 0 {
            let a = NSAlert()
            a.messageText = "\(failed) 个项目删除失败"
            a.runModal()
        }
        reload()
    }

    @objc func doRename() {
        guard let item = selectedItem(), !item.isParent else { return }
        if isArchiveMode, let archive = currentArchiveURL, let path = item.archivePath {
            let d = TextInputDialog(title: "重命名", prompt: "新名称:", defaultValue: item.name)
            guard let newName = d.runModal(on: window), !newName.isEmpty, newName != item.name else { return }
            let parts = path.split(separator: "/").map(String.init)
            let newFull = (parts.dropLast().isEmpty ? "" : parts.dropLast().joined(separator: "/") + "/") + newName
            let args = ["rn", "-y", "-bsp1", archive.path, path, newFull]
            OperationRunner.shared.start(args: args, title: "重命名", window: window) { [weak self] ok, msg in
                if !ok {
                    let a = NSAlert(); a.messageText = "重命名失败"; a.informativeText = msg; a.runModal()
                }
                self?.navigateToArchive(archive, password: self?.archivePassword ?? "")
            }
            return
        }
        guard let url = item.fileURL else { return }
        let d = TextInputDialog(title: "重命名", prompt: "新名称:", defaultValue: item.name)
        guard let newName = d.runModal(on: window), !newName.isEmpty else { return }
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
            reload()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc func doProperties() {
        let info = InfoDialog(panel: self)
        info.runModal(on: window)
    }

    // MARK: Copy / Paste / Move

    @objc func doCopy() {
        let sel = selectedItems()
        guard !sel.isEmpty else { return }
        PanelClipboard.clear()
        PanelClipboard.isMove = false
        if isArchiveMode, let archive = currentArchiveURL {
            let currentInner: String = { if case .archive(_, let i) = location { return i }; return "" }()
            let entries = sel.map { item -> String in
                if let p = item.archivePath { return p }
                return currentInner.isEmpty ? item.name : currentInner + "/" + item.name
            }
            PanelClipboard.fromArchive = (archive, entries)
        } else {
            PanelClipboard.sources = sel.compactMap { $0.fileURL }
        }
    }

    @objc func doMove() {
        doCopy()
        PanelClipboard.isMove = true
    }

    @objc func doPaste() {
        guard case .folder(let destDir) = location else { return }
        if let fromArchive = PanelClipboard.fromArchive {
            var args = ["x", "-y", "-bsp1"]
            args.append("-o\(destDir.path)")
            args.append(fromArchive.url.path)
            args.append(contentsOf: fromArchive.entries)
            OperationRunner.shared.start(args: args, title: "复制(从压缩包)", window: window) { [weak self] ok, msg in
                if !ok {
                    let a = NSAlert(); a.messageText = "复制失败"; a.informativeText = msg; a.runModal()
                }
                self?.reload()
                if PanelClipboard.isMove { PanelClipboard.clear() }
            }
            return
        }
        let sources = PanelClipboard.sources
        guard !sources.isEmpty else { return }
        let fm = FileManager.default
        var failed = 0
        for src in sources {
            let target = destDir.appendingPathComponent(src.lastPathComponent)
            do {
                if fm.fileExists(atPath: target.path) {
                    try fm.removeItem(at: target)
                }
                if PanelClipboard.isMove {
                    try fm.moveItem(at: src, to: target)
                } else {
                    try fm.copyItem(at: src, to: target)
                }
            } catch { failed += 1 }
        }
        if failed > 0 {
            let a = NSAlert()
            a.messageText = "\(failed) 个项目复制/移动失败"
            a.runModal()
        }
        reload()
        if PanelClipboard.isMove { PanelClipboard.clear() }
    }

    // MARK: Open file from archive

    func extractAndOpen(item: PanelItem, archive: URL) {
        guard let path = item.archivePath else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("BingZipOpen-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        var args = ["x", "-y", "-bsp1", "-o\(tmp.path)"]
        if !archivePassword.isEmpty { args.append("-p\(archivePassword)") }
        args.append(archive.path)
        args.append(path)
        OperationRunner.shared.start(args: args, title: "打开: \(item.name)", window: window) { _, _ in
            let opened = tmp.appendingPathComponent(item.name)
            NSWorkspace.shared.open(opened)
            DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
                try? FileManager.default.removeItem(at: tmp)
            }
        }
    }

    // MARK: - 扫描(批量检查压缩包)

    /// 扫描当前文件夹(含所有子目录)里的压缩包,汇总正常 / 损坏数量
    @objc func doScanArchives() {
        guard case .folder(let dir) = location else {
            let a = NSAlert()
            a.messageText = "请先进入一个文件夹"
            a.informativeText = "“扫描”会检查当前文件夹及其所有子文件夹里的压缩包。"
            a.addButton(withTitle: "知道了")
            a.runModal()
            return
        }

        // 递归扫描最容易触发逐个文件夹的 TCC 授权提示,
        // 先统一引导开启“完全磁盘访问”。
        guard SystemPermissions.confirmFullDiskAccessForScan(on: window) else { return }

        let archives = Self.collectArchives(in: dir, limit: 3000)
        guard !archives.isEmpty else {
            let a = NSAlert()
            a.messageText = "没有找到压缩包"
            a.informativeText = "当前文件夹及其子文件夹里没有可检查的压缩包。"
            a.addButton(withTitle: "知道了")
            a.runModal()
            return
        }

        let flag = ScanCancelFlag()
        let pc = ProgressWindowController(title: "扫描: \(dir.lastPathComponent)")
        taskWindows.append(pc)
        pc.onCancel = { flag.cancel() }
        pc.showWindow(nil)
        pc.window?.center()
        pc.setOverall(0, status: "共 \(archives.count) 个压缩包,开始检查…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var okCount = 0
            var skipped = 0
            var bad: [String] = []
            for (i, a) in archives.enumerated() {
                if flag.isCancelled { break }
                switch Self.checkArchive(a) {
                case .ok: okCount += 1
                case .needsPassword: skipped += 1
                case .damaged: bad.append(a.path)
                }
                let pct = Double(i + 1) / Double(archives.count) * 100
                DispatchQueue.main.async {
                    pc.setOverall(pct, status: "正在检查 \(i + 1)/\(archives.count):\(a.lastPathComponent)")
                }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.taskWindows.removeAll { $0 === pc }
                pc.finish(success: true, message: "")
                pc.window?.orderOut(nil)
                self.showScanResult(total: archives.count, ok: okCount,
                                    bad: bad, skipped: skipped, cancelled: flag.isCancelled)
            }
        }
    }

    /// 递归收集压缩包文件
    static func collectArchives(in dir: URL, limit: Int) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        guard let en = fm.enumerator(at: dir,
                                     includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        for case let url as URL in en {
            if out.count >= limit { break }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            if isKnownArchive(url) { out.append(url) }
        }
        return out
    }

    private func showScanResult(total: Int, ok: Int, bad: [String], skipped: Int, cancelled: Bool) {
        var lines: [String] = []
        lines.append("共检查 \(total) 个压缩包")
        lines.append("正常 \(ok) 个")
        lines.append("损坏 \(bad.count) 个")
        if skipped > 0 { lines.append("需要密码,已跳过 \(skipped) 个") }
        if cancelled { lines.append("(扫描被中途停止)") }

        if !bad.isEmpty {
            lines.append("")
            lines.append("损坏的压缩包:")
            for p in bad.prefix(12) { lines.append("• \(p)") }
            if bad.count > 12 { lines.append("… 其余 \(bad.count - 12) 个已写入日志") }
            AppLogger.shared.log("SCAN bad archives:\n" + bad.joined(separator: "\n"))
        }

        let alert = NSAlert()
        alert.messageText = bad.isEmpty ? "扫描完成:全部正常" : "扫描完成:发现 \(bad.count) 个损坏"
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - One-click operations (傻瓜式)

    /// Compress the selection (or current folder) to a sibling .7z with sane defaults.
    @objc func doQuickCompress() {
        var sources: [URL] = selectedItems().compactMap { $0.fileURL }
        if sources.isEmpty {
            if case .folder(let url) = location { sources = [url] }
            else if let a = currentArchiveURL { sources = [a] }
        }
        guard let first = sources.first else { return }
        let base = first.deletingPathExtension().lastPathComponent
        let dir = first.deletingLastPathComponent()
        var archive = dir.appendingPathComponent(base + ".7z")
        var counter = 2
        while FileManager.default.fileExists(atPath: archive.path) {
            archive = dir.appendingPathComponent("\(base) \(counter).7z")
            counter += 1
        }
        var args = ["a", "-y", "-bsp1", "-t7z", "-mx=5", archive.path]
        args.append(contentsOf: sources.map { $0.path })
        OperationRunner.shared.start(args: args,
                                     title: "快速压缩: \(archive.lastPathComponent)",
                                     window: window) { [weak self] ok, _ in
            self?.reload()
            self?.otherPanel?.reload()
            if ok {
                DispatchQueue.main.async {
                    HashResultWindow(archiveURL: archive).showWindow(nil)
                }
            }
        }
    }

    /// Extract the selected archive into a sibling folder using safe defaults.
    @objc func doQuickExtract() {
        var archive: URL? = currentArchiveURL
        if archive == nil {
            archive = selectedItems().compactMap { $0.fileURL }.first { isKnownArchive($0) }
        }
        guard let a = archive else { return }
        var dest = a.deletingPathExtension()
        var counter = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = a.deletingPathExtension()
            dest = dest.deletingLastPathComponent()
                .appendingPathComponent(a.deletingPathExtension().lastPathComponent + " \(counter)")
            counter += 1
        }
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let args = ["x", "-y", "-bsp1", "-aos", "-o\(dest.path)", a.path]
        OperationRunner.shared.start(args: args,
                                     title: "快速解压: \(a.lastPathComponent)",
                                     window: window) { [weak self] ok, _ in
            self?.reload()
            if ok { NSWorkspace.shared.open(dest) }
        }
    }

/// 扫描取消标记(线程安全)
final class ScanCancelFlag {
    private let lock = NSLock()
    private var value = false

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}


/// 压缩包检查结果
enum ArchiveCheckResult {
    case ok
    case needsPassword
    case damaged(String)
}

}