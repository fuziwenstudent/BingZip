import Foundation
import AppKit

extension AddDialog {

    @objc func settingsChanged() {
        updateMemoryLabel()
    }

    func updateMemoryLabel() {
        let method = methodPopup.titleOfSelectedItem ?? ""
        let level = ArgsBuilder.levels[levelPopup.indexOfSelectedItem].1
        memLabel.stringValue = "内存使用: " + ArgsBuilder.estimateMemory(
            method: method, dictSize: dictPopup.titleOfSelectedItem, level: level)
    }

    @objc func formatChanged() {
        let fmt = formatPopup.titleOfSelectedItem ?? "7z"
        syncArchiveExtension(to: fmt)
        let selectedMethod = methodPopup.titleOfSelectedItem
        methodPopup.removeAllItems()
        methodPopup.addItems(withTitles: ArgsBuilder.methods(for: fmt))
        if let m = selectedMethod, ArgsBuilder.methods(for: fmt).contains(m) {
            methodPopup.selectItem(withTitle: m)
        }
        dictPopup.removeAllItems()
        dictPopup.addItems(withTitles: ArgsBuilder.dictSizes(for: methodPopup.titleOfSelectedItem))
        let sizes = ArgsBuilder.dictSizes(for: methodPopup.titleOfSelectedItem)
        if sizes.count > 9 { dictPopup.selectItem(withTitle: sizes[9]) }
        // Header encryption is a 7z-only feature (RAR uses -hp through its own tool)
        if fmt.lowercased() != "7z" {
            encryptHeaderButton.state = .off
        }
        encryptHeaderButton.isEnabled = (fmt.lowercased() == "7z")
        if fmt.lowercased() == "rar" {
            RarTool.shared.reload()
            hintLabel?.stringValue = RarTool.shared.isAvailable
                ? "RAR 压缩将使用 RARLAB 的 rar 工具创建(RAR5 格式)。"
                : "创建 RAR 需要 RARLAB 的 rar 工具;7-Zip 引擎只能解压 RAR。"
            hintLabel?.textColor = RarTool.shared.isAvailable ? .secondaryLabelColor : .systemOrange
        } else {
            hintLabel?.stringValue = "提示:压缩程度越高,文件越小,但需要的时间更长。"
            hintLabel?.textColor = .secondaryLabelColor
        }
        updateMemoryLabel()
    }

    /// 切换格式时同步"压缩包"字段的扩展名(与 7-Zip 官方 GUI 行为一致),
    /// 否则选了 Zip 仍会输出名为 xxx.7z 的文件。
    func syncArchiveExtension(to format: String) {
        let ext = ArgsBuilder.fileExtension(for: format)
        var path = archiveField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }
        let current = (path as NSString).pathExtension.lowercased()
        if current.isEmpty {
            path += ".\(ext)"
        } else if knownArchiveExtensions.contains(current), current != ext {
            path = (path as NSString).deletingPathExtension + ".\(ext)"
        } else {
            return
        }
        archiveField.stringValue = path
    }

    @objc func browseDest() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = []
        panel.message = "选择压缩包保存位置"
        let fmt = formatPopup.titleOfSelectedItem ?? "7z"
        panel.nameFieldStringValue = archiveField.stringValue
        if panel.runModal() == .OK, let url = panel.url {
            let ext = ArgsBuilder.fileExtension(for: fmt)
            archiveField.stringValue = url.path + (url.pathExtension.isEmpty ? "." + ext : "")
        }
    }

    @objc func cancelClick() {
        window?.orderOut(nil)
        NSApp.stopModal()
    }

    @objc func okClick() {
        let pw1 = passwordField.stringValue
        let pw2 = password2Field.stringValue
        if !pw1.isEmpty && pw1 != pw2 {
            let a = NSAlert()
            a.messageText = "两次输入的密码不一致"
            a.runModal()
            return
        }

        var fmt = formatPopup.titleOfSelectedItem ?? "7z"
        if fmt.lowercased() == "rar" {
            RarTool.shared.reload()
            if !RarTool.shared.isAvailable {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = "创建 RAR 需要 RARLAB 的 rar 工具"
                alert.informativeText = """
                RAR 是专有格式,内置的 7-Zip 引擎只能解压 RAR,不能创建。
                请安装 RARLAB 官方 rar 命令行工具,或在设置中指定它的位置。
                安装后可放在 /usr/local/bin/rar,或设置 BINGZIP_RAR 环境变量。
                """
                alert.addButton(withTitle: "打开下载页面")
                alert.addButton(withTitle: "改用 ZIP 压缩")
                alert.addButton(withTitle: "取消")
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(AppInfo.rarDownloadPage)
                    return
                } else if response == .alertSecondButtonReturn {
                    fmt = "Zip"
                    formatPopup.selectItem(withTitle: "Zip")
                    formatChanged()
                } else {
                    return
                }
            }
        }
        let level = ArgsBuilder.levels[levelPopup.indexOfSelectedItem].1
        let method = methodPopup.titleOfSelectedItem ?? ""

        // dictionary / word size / solid
        var dictSize: String? = dictPopup.titleOfSelectedItem
        if method == "Copy" || method == "Deflate" || method == "Deflate64" { dictSize = nil }

        var threads: Int? = nil
        if let t = threadsPopup.titleOfSelectedItem, let n = Int(t) { threads = n }
        var solid: String? = nil
        switch solidPopup.indexOfSelectedItem {
        case 1: solid = "on"
        case 2: solid = "off"
        default: solid = nil
        }

        var volume: String? = nil
        let volText = volumeField.stringValue.trimmingCharacters(in: .whitespaces)
        if !volText.isEmpty, let n = Int(volText), n > 0 {
            switch volumeUnitPopup.indexOfSelectedItem {
            case 0: volume = "\(n)"
            case 1: volume = "\(n)k"
            case 3: volume = "\(n)g"
            default: volume = "\(n)m"
            }
        }

        var updateMode = ""
        if updatePopup.indexOfSelectedItem == 1 { updateMode = "u" }

        var pathMode = ""
        switch pathModePopup.indexOfSelectedItem {
        case 1: pathMode = "-spf"
        case 2: pathMode = "-spf2"
        case 3: pathMode = "-ep"
        default: break
        }

        var archivePath = URL(fileURLWithPath: archiveField.stringValue)
        // auto-append / correct extension so it always matches the chosen format
        let ext = ArgsBuilder.fileExtension(for: fmt)
        if archivePath.pathExtension.isEmpty {
            archivePath = URL(fileURLWithPath: archiveField.stringValue + "." + ext)
        } else if knownArchiveExtensions.contains(archivePath.pathExtension.lowercased()),
                  archivePath.pathExtension.lowercased() != ext {
            // 选了 Zip 却仍是 xxx.7z 时以所选格式为准,避免产出名不副实
            archivePath = archivePath.deletingPathExtension().appendingPathExtension(ext)
        }
        try? FileManager.default.createDirectory(
            at: archivePath.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        let excludes: [String] = excludeField.stringValue
            .split(whereSeparator: { $0 == ";" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let extraParams = paramsField.stringValue.trimmingCharacters(in: .whitespaces)

        // RAR creation is delegated to RARLAB's `rar` tool (7-Zip only reads RAR).
        if fmt.lowercased() == "rar" {
            let request = RarTool.AddRequest(
                archivePath: archivePath,
                files: sources,
                level: level,
                password: pw1.isEmpty ? nil : pw1,
                encryptHeader: encryptHeaderButton.state == .on,
                volume: volume,
                deleteSource: deleteSourceButton.state == .on,
                storeSymlinks: symlinkButton.state == .on,
                excludes: excludes,
                threads: threads,
                dictSize: dictSize,
                extraParams: extraParams)
            do {
                let invocation = try RarTool.shared.makeAddInvocation(request)
                window?.orderOut(nil)
                NSApp.stopModal()
                let onFinish = self.completion
                OperationRunner.shared.start(
                    args: invocation.args,
                    title: "压缩到: \(archivePath.lastPathComponent)",
                    window: window,
                    executable: invocation.executable,
                    workingDirectory: invocation.workingDirectory) { ok, _ in
                    onFinish?()
                    if ok {
                        DispatchQueue.main.async {
                            HashResultWindow(archiveURL: archivePath).showWindow(nil)
                        }
                    }
                }
            } catch {
                NSAlert(error: error).runModal()
            }
            return
        }

        let command: String = updateMode == "u" ? "u" : "a"
        var args = [command, "-y", "-bsp1", "-t\(fmt.lowercased())"]
        if level >= 0 { args.append("-mx=\(level)") }
        if !method.isEmpty { args.append("-m0=\(method)") }
        if let d = dictSize, !d.isEmpty { args.append("-md=\(d)") }
        if let w = Int(wordField.stringValue), w > 0 { args.append("-mfb=\(w)") }
        if let t = threads { args.append("-mmt=\(t)") }
        if let s = solid { args.append("-ms=\(s)") }
        if !pathMode.isEmpty { args.append(pathMode) }
        if !pw1.isEmpty {
            args.append("-p\(pw1)")
            if fmt.lowercased() == "7z" && encryptHeaderButton.state == .on {
                args.append("-mhe=on")
            }
            if fmt.lowercased() == "zip" {
                // WinZip-compatible AES-256 encryption for zip archives
                args.append("-mem=AES256")
            }
        }
        if fmt.lowercased() == "zip" {
            // 代码页设置(仅 Zip):兼容旧版 Windows 解压器的文件名编码
            let cp = UserDefaults.standard.string(forKey: "BingZipCodePage") ?? ""
            if !cp.isEmpty { args.append("-mcp=\(cp)") }
        }
        if let v = volume { args.append("-v\(v)") }
        // Engine / safety options
        if deleteSourceButton.state == .on { args.append("-sdel") }
        if symlinkButton.state == .on { args.append("-snl") }
        for pattern in excludes { args.append("-x!\(pattern)") }
        if !extraParams.isEmpty {
            args.append(contentsOf: extraParams.split(separator: " ").map(String.init))
        }
        args.append(archivePath.path)
        args.append(contentsOf: sources.map { $0.path })

        window?.orderOut(nil)
        NSApp.stopModal()
        let onFinish = self.completion
        OperationRunner.shared.start(args: args, title: "压缩到: \(archivePath.lastPathComponent)", window: window) { ok, _ in
            onFinish?()
            if ok {
                // Auto-show MD5 / SHA256 with copy buttons (傻瓜式: 一眼可见、可复制)
                DispatchQueue.main.async {
                    HashResultWindow(archiveURL: archivePath).showWindow(nil)
                }
            }
        }
    }
}