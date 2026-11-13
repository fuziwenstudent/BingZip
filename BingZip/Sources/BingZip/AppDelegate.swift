import AppKit
import Carbon

enum SortColumn: Int {
    case name = 0, size, packedSize, type, modified, crc, attributes

    var title: String {
        switch self {
        case .name: return "名称"
        case .size: return "大小"
        case .packedSize: return "压缩大小"
        case .type: return "类型"
        case .modified: return "修改时间"
        case .crc: return "CRC"
        case .attributes: return "属性"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {

    var windows: [MainWindowController] = []

    /// 由 Finder 右键 / 服务 / bingzip:// 命令启动时为 true:
    /// 此时不自动显示主窗口,只显示压缩或解压对话框。
    private var launchedForExternalCommand = false
    private var launchEventChecked = false
    private var handledExternalCommand = false
    private var didFinishLaunching = false
    private var initialWindowFallback: DispatchWorkItem?
    private var pendingLaunchActions: [() -> Void] = []

    /// 文件列表相关快捷键。主窗口且非文本编辑时启用;
    /// 对话框 / 文本框编辑时临时移除,避免抢走 ⌘C、⌘⌫、⌘↑ 等编辑按键。
    private var shortcutEntries: [(item: NSMenuItem, key: String,
                                   modifiers: NSEvent.ModifierFlags)] = []
    private var shortcutsSuspended = false
    private var shortcutObserversInstalled = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        captureLaunchEvent()
    }

    /// 正常双击 App 启动时,启动事件是 kAEOpenApplication。
    /// URL Scheme、Finder 打开文件、服务菜单会带来其它事件,
    /// 这些场景不应该先弹出主窗口。
    /// `currentAppleEvent` 在部分系统上要等到 didFinish 阶段才可用,
    /// 因此两个阶段都尝试一次。
    private func captureLaunchEvent() {
        guard !launchEventChecked else { return }
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return }
        launchEventChecked = true
        let cls = event.eventClass
        let eid = event.eventID
        let isPlainLaunch = cls == AEEventClass(kCoreEventClass)
            && eid == AEEventID(kAEOpenApplication)
        launchedForExternalCommand = !isPlainLaunch
        AppLogger.shared.log("Launch event class=\(cls) id=\(eid) external=\(!isPlainLaunch)")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        captureLaunchEvent()
        AppLogger.shared.installCrashHandlers()
        checkEngine()
        NSLog("BingZip: applicationDidFinishLaunching begin")
        NSRegisterServicesProvider(self, "BingZip")
        NSApp.mainMenu = buildMenu()
        installShortcutObservers()
        didFinishLaunching = true

        if handledExternalCommand {
            // 打开事件已先到,由它自己决定是否显示主窗口。
        } else if launchedForExternalCommand {
            // Finder 命令 / URL 事件可能在启动完成前后到达。
            // 给它们一个短暂窗口;若什么也没收到,仍回退到主窗口。
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if !self.handledExternalCommand && self.windows.isEmpty {
                    self.showInitialWindow()
                }
            }
            initialWindowFallback = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
        } else {
            showInitialWindow()
        }

        // 上次崩溃 → 本次启动自动显示崩溃报告(优先于权限检查)
        // 右键一次性命令不打扰用户,不弹权限 / 崩溃提示。
        if !launchedForExternalCommand && !handledExternalCommand {
            scheduleCrashReportCheck()
            schedulePermissionsCheck()
        }

        // 不要在 applicationDidFinishLaunching 里同步启动模态循环。
        let actions = pendingLaunchActions
        pendingLaunchActions.removeAll()
        if !actions.isEmpty {
            DispatchQueue.main.async {
                actions.forEach { $0() }
            }
        }

        NSLog("BingZip: applicationDidFinishLaunching end")
    }

    /// 直接上屏:NSWindowController.showWindow 在带文档启动时会走 QuickLook 无缝动画,可能卡死
    private func showInitialWindow() {
        let w: MainWindowController
        if let first = windows.first {
            w = first
        } else {
            w = MainWindowController()
            windows.append(w)
        }
        w.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        w.focusInitialResponder()
    }

    /// 标记本次启动已由外部命令接管,取消“回退到主窗口”的定时器。
    private func markExternalCommandHandled() {
        handledExternalCommand = true
        initialWindowFallback?.cancel()
        initialWindowFallback = nil
    }

    /// 在启动流程结束前,把需要弹窗的动作延后执行。
    private func runAfterLaunch(_ action: @escaping () -> Void) {
        if didFinishLaunching {
            action()
        } else {
            pendingLaunchActions.append(action)
        }
    }

    // MARK: - Context-sensitive shortcuts

    /// 记录菜单项原始快捷键,方便临时挂起 / 恢复。
    private func registerShortcut(_ item: NSMenuItem) {
        shortcutEntries.append((item, item.keyEquivalent, item.keyEquivalentModifierMask))
    }

    private func installShortcutObservers() {
        guard !shortcutObserversInstalled else { return }
        shortcutObserversInstalled = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(windowKeyStateChanged(_:)),
                       name: NSWindow.didBecomeKeyNotification, object: nil)
        nc.addObserver(self, selector: #selector(windowKeyStateChanged(_:)),
                       name: NSWindow.didResignKeyNotification, object: nil)
        nc.addObserver(self, selector: #selector(textEditingStateChanged(_:)),
                       name: NSControl.textDidBeginEditingNotification, object: nil)
        nc.addObserver(self, selector: #selector(textEditingStateChanged(_:)),
                       name: NSControl.textDidEndEditingNotification, object: nil)
    }

    @objc private func windowKeyStateChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateShortcutAvailability()
        }
    }

    @objc private func textEditingStateChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateShortcutAvailability()
        }
    }

    private func updateShortcutAvailability() {
        let keyWindow = NSApp.keyWindow
        let mainWindowIsKey = keyWindow?.windowController is MainWindowController
        let isEditingText = keyWindow?.firstResponder is NSTextView
        let shouldSuspend = !mainWindowIsKey || isEditingText
        guard shouldSuspend != shortcutsSuspended else { return }
        shortcutsSuspended = shouldSuspend
        for entry in shortcutEntries {
            entry.item.keyEquivalent = shouldSuspend ? "" : entry.key
            entry.item.keyEquivalentModifierMask = shouldSuspend ? [] : entry.modifiers
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Engine self-test at startup: report a friendly error instead of failing silently.
    private func checkEngine() {
        let engine = SevenZip.shared.binaryURL
        if !FileManager.default.isExecutableFile(atPath: engine.path) {
            AppLogger.shared.log("ERROR: engine missing at \(engine.path)")
            let a = NSAlert()
            a.messageText = "压缩引擎不可用"
            a.informativeText = "未找到 7zz 引擎:\n\(engine.path)\n\n请重新安装 BingZip,或设置 BINGZIP_7ZZ 环境变量指向 7zz。"
            a.runModal()
            return
        }
        if let r = try? SevenZip.shared.run(["i"]) {
            if r.exitCode == 0 {
                AppLogger.shared.log("Engine OK: \(engine.path)")
            } else {
                AppLogger.shared.log("ERROR: engine self-test failed exit=\(r.exitCode) stderr=\(r.stderr.prefix(300))")
            }
        }
    }

    // Finder opens files with BingZip (double click / Open With / drag to Dock)
    // and the Finder Sync extension sends bingzip:// commands.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        markExternalCommandHandled()

        if didFinishLaunching {
            processOpenURLs(urls)
        } else {
            // 极少数系统版本会在启动完成前投递打开事件,延后到启动完成再处理。
            pendingLaunchActions.append { [weak self] in
                self?.processOpenURLs(urls)
            }
        }
    }

    private func processOpenURLs(_ urls: [URL]) {
        if let command = urls.first(where: { $0.scheme?.lowercased() == "bingzip" }) {
            handleFinderCommand(command)
            return
        }

        let fileURLs = urls.filter { $0.isFileURL }
        guard !fileURLs.isEmpty else { return }

        // 单个压缩包 → 在主窗口中浏览(这是主界面本身的功能)。
        // 多个文件 / 普通文件 / 文件夹 → 只弹压缩对话框,不打开主界面。
        if fileURLs.count == 1, isKnownArchive(fileURLs[0]) {
            let w = activateWindow()
            w.leftPanel.navigate(toFile: fileURLs[0])
        } else {
            presentAddDialog(files: fileURLs)
        }
    }

    @discardableResult
    private func activateWindow() -> MainWindowController {
        let w: MainWindowController
        if let first = windows.first {
            w = first
        } else {
            w = MainWindowController()
            windows.append(w)
        }
        w.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        w.focusInitialResponder()
        return w
    }

    /// 只显示压缩对话框,不创建 / 显示主窗口。
    private func presentAddDialog(files: [URL]) {
        guard let first = files.first else { return }
        runAfterLaunch { [weak self] in
            // 不要在 application(_:open:) / Apple Event 回调里同步启动模态循环,
            // 否则系统会在事件处理结束后结束模态会话。
            DispatchQueue.main.async {
                self?.bringAppToFront()
                let dialog = AddDialog(sources: files,
                                       suggestDirectory: first.deletingLastPathComponent())
                dialog.runModal(on: nil) {}
            }
        }
    }

    /// 只显示解压对话框,不创建 / 显示主窗口。
    private func presentExtractDialog(archive: URL) {
        runAfterLaunch { [weak self] in
            // 同 presentAddDialog:延后到 Apple Event 回调之外再启动模态循环。
            DispatchQueue.main.async {
                self?.bringAppToFront()
                let dialog = ExtractDialog(archive: archive, files: nil,
                                           suggestDirectory: archive.deletingLastPathComponent())
                dialog.runModal(on: nil) {}
            }
        }
    }

    private func bringAppToFront() {
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 右键压缩/解压对话框仍在前台时,不要在其后创建主窗口。
        guard NSApp.modalWindow == nil else { return true }
        if !flag {
            showInitialWindow()
        }
        return true
    }

    /// 上次崩溃后,本次启动自动显示崩溃报告。等待其它模态窗口关闭。
    private func scheduleCrashReportCheck(attempt: Int = 0) {
        let delay: TimeInterval = attempt == 0 ? 0.8 : 3.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            if NSApp.modalWindow != nil {
                if attempt < 20 { self.scheduleCrashReportCheck(attempt: attempt + 1) }
                return
            }
            CrashReportPresenter.presentIfNeeded(on: self.windows.first?.window)
        }
    }

    /// Startup permission check. Waits until no modal dialog (for example the
    /// crash report or an Add dialog) is on screen.
    private func schedulePermissionsCheck(attempt: Int = 0) {
        let delay: TimeInterval = attempt == 0 ? 1.0 : 5.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            guard SystemPermissions.isStartupCheckEnabled else { return }
            if NSApp.modalWindow != nil {
                if attempt < 6 { self.schedulePermissionsCheck(attempt: attempt + 1) }
                return
            }
            SystemPermissions.checkAtLaunch(parent: self.windows.first?.window)
        }
    }

    /// Handle `bingzip://compress?path=…`, `bingzip://extract?path=…` and
    /// `bingzip://open?path=…` sent by the Finder extension
    /// (paths are percent-encoded query items).
    private func handleFinderCommand(_ url: URL) {
        markExternalCommandHandled()

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            AppLogger.shared.log("Finder command: invalid URL \(url.absoluteString)")
            return
        }
        let rawAction = components.host?.isEmpty == false ? components.host! : components.path
        let action = rawAction.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let paths = (components.queryItems ?? [])
            .filter { $0.name == "path" }
            .compactMap { $0.value }
            .filter { !$0.isEmpty }

        let files = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        guard !files.isEmpty else {
            AppLogger.shared.log("Finder command \(action): no existing paths")
            return
        }

        AppLogger.shared.log("Finder command \(action): \(files.count) item(s)")

        switch action {
        case "compress":
            // 只显示压缩对话框,不打开主界面
            presentAddDialog(files: files)
        case "extract":
            guard let archive = files.first(where: isKnownArchive) else {
                showFinderError(title: "无法解压",
                                message: "选中的文件不是 BingZip 支持的压缩包格式。")
                return
            }
            // 只显示解压对话框,不打开主界面
            presentExtractDialog(archive: archive)
        case "open":
            // “打开压缩包”本身就是在主界面中浏览
            let w = activateWindow()
            if let archive = files.first(where: isKnownArchive) {
                w.leftPanel.navigate(toFile: archive)
            } else {
                showFinderError(title: "无法打开压缩包",
                                message: "选中的文件不是 BingZip 支持的压缩包格式。")
            }
        default:
            AppLogger.shared.log("Finder command: unknown action \(action)")
        }
    }

    private func showFinderError(title: String, message: String) {
        bringAppToFront()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - Finder Services (right click > Services)

    @objc func serviceAddToArchive(_ pboard: NSPasteboard, userData: String,
                                   error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urls = pboard.readObjects(forClasses: [NSURL.self],
                                            options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else {
            error.pointee = "没有可压缩的文件"
            return
        }
        markExternalCommandHandled()
        presentAddDialog(files: urls)
    }

    @objc func serviceExtractArchive(_ pboard: NSPasteboard, userData: String,
                                     error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urls = pboard.readObjects(forClasses: [NSURL.self],
                                            options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else {
            error.pointee = "没有可解压的文件"
            return
        }
        guard let archive = urls.first(where: { isKnownArchive($0) }) else {
            error.pointee = "选中的文件不是支持的压缩包"
            return
        }
        markExternalCommandHandled()
        presentExtractDialog(archive: archive)
    }

    func removeWindow(_ w: MainWindowController) {
        windows.removeAll { $0 === w }
        if windows.isEmpty { NSApp.terminate(nil) }
    }

    private var keyWindow: MainWindowController? {
        if let w = NSApp.keyWindow?.windowController as? MainWindowController { return w }
        // 对话框 / 面板是当前键盘窗口时,不要退回到后台主窗口执行文件操作。
        if NSApp.keyWindow != nil { return nil }
        return windows.first
    }

    // MARK: - Menu actions

    @objc func menuNewWindow(_ s: Any?) {
        // 模态对话框期间不创建主窗口,避免窗口出现在对话框后面。
        guard NSApp.modalWindow == nil else { return }
        let w = MainWindowController(); windows.append(w)
        w.window?.makeKeyAndOrderFront(nil)
        w.focusInitialResponder()
    }
    @objc func menuOpenSelection(_ s: Any?) { keyWindow?.activePanel.openSelected() }
    @objc func menuGoBack(_ s: Any?) { keyWindow?.activePanel.goBack() }
    @objc func menuGoForward(_ s: Any?) { keyWindow?.activePanel.goForward() }
    @objc func menuGoUp(_ s: Any?) { keyWindow?.activePanel.navigateUp() }
    @objc func menuClose(_ s: Any?) {
        // ⌘W 关闭当前键盘窗口:对话框关闭自身,主窗口正常退出。
        if let current = NSApp.keyWindow {
            current.performClose(s)
        } else {
            keyWindow?.window?.close()
        }
    }
    @objc func menuOpenArchive(_ s: Any?) { keyWindow?.openArchiveDialog() }
    @objc func menuAdd(_ s: Any?) { keyWindow?.activePanel.doAdd() }
    @objc func menuExtract(_ s: Any?) { keyWindow?.activePanel.doExtract() }
    @objc func menuTest(_ s: Any?) { keyWindow?.activePanel.doTest() }
    @objc func menuQuickCompress(_ s: Any?) { keyWindow?.activePanel.doQuickCompress() }
    @objc func menuQuickExtract(_ s: Any?) { keyWindow?.activePanel.doQuickExtract() }
    @objc func menuNewFolder(_ s: Any?) { keyWindow?.activePanel.doNewFolder() }
    @objc func menuDelete(_ s: Any?) { keyWindow?.activePanel.doDelete() }
    @objc func menuRename(_ s: Any?) { keyWindow?.activePanel.doRename() }
    @objc func menuProperties(_ s: Any?) { keyWindow?.activePanel.doProperties() }
    @objc func menuCopy(_ s: Any?) { keyWindow?.activePanel.doCopy() }
    @objc func menuPaste(_ s: Any?) { keyWindow?.activePanel.doPaste() }
    @objc func menuMove(_ s: Any?) { keyWindow?.activePanel.doMove() }
    @objc func menuSelectAll(_ s: Any?) { keyWindow?.activePanel.doSelectAll() }
    @objc func menuInvertSelection(_ s: Any?) { keyWindow?.activePanel.doInvertSelection() }
    @objc func menuRefresh(_ s: Any?) { keyWindow?.activePanel.doRefresh() }
    @objc func menuAddBookmark(_ s: Any?) { keyWindow?.addBookmark() }
    @objc func menuBench(_ s: Any?) { BenchDialog().runModal(on: keyWindow?.window) }
    @objc func menuHash(_ s: Any?) { HashDialog().runModal(on: keyWindow?.window) }
    @objc func menuSettings(_ s: Any?) { SettingsDialog().runModal(on: keyWindow?.window) }
    @objc func menuAbout(_ s: Any?) { AboutDialog().runModal(on: keyWindow?.window) }
    @objc func menuFormats(_ s: Any?) { FormatInfoDialog().runModal(on: keyWindow?.window) }
    @objc func menuBackgroundTasks(_ s: Any?) { OperationRunner.shared.restoreRunningWindows() }
    @objc func menuOpenLogs(_ s: Any?) { NSWorkspace.shared.open(AppLogger.shared.logDirectory) }
    @objc func menuExportLogs(_ s: Any?) { LogActions.export(from: keyWindow?.window) }
    @objc func menuClearLogs(_ s: Any?) { LogActions.clearAll(from: keyWindow?.window) }
    @objc func menuPermissions(_ s: Any?) { PermissionsDialog().runModal(on: keyWindow?.window) }
    @objc func menuWebsite(_ s: Any?) { NSWorkspace.shared.open(AppInfo.websiteURL) }

    @objc func menuToggleSidebar(_ s: Any?) {
        menuToggleTree(s)
    }

    /// 显示 / 隐藏左侧目录树
    @objc func menuToggleTree(_ s: Any?) {
        let key = "BingZipShowTree"
        let current = UserDefaults.standard.object(forKey: key) as? Bool ?? true
        let next = !current
        UserDefaults.standard.set(next, forKey: key)
        if let item = s as? NSMenuItem { item.state = next ? .on : .off }
        for w in windows { w.showTree(next) }
    }

    @objc func menuFind(_ s: Any?) {
        let w = keyWindow
        let d = TextInputDialog(title: "查找", prompt: "按名称筛选当前列表:", defaultValue: w?.activePanel.filterText ?? "")
        if let text = d.runModal(on: w?.window) {
            w?.activePanel.filterText = text
        }
    }

    @objc func menuClearFilter(_ s: Any?) {
        keyWindow?.activePanel.filterText = ""
    }

    @objc func menuCodePage(_ s: Any?) {
        keyWindow?.codePageAction()
    }

    /// Install the 7zz engine as a `bingzip` CLI tool in ~/.local/bin
    @objc func menuInstallCLI(_ s: Any?) {
        let alert = NSAlert()
        alert.messageText = "安装命令行工具"
        alert.informativeText = "将在 ~/.local/bin/bingzip 安装 7-Zip 引擎副本,可在终端直接使用 bingzip 命令。"
        alert.addButton(withTitle: "安装")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent("bingzip")
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: SevenZip.shared.binaryURL, to: dest)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)

            let ok = NSAlert()
            ok.messageText = "安装成功"
            ok.informativeText = "已安装: \(dest.path)\n\n如果命令不可用,请把 ~/.local/bin 加入 PATH:\nexport PATH=\"$HOME/.local/bin:$PATH\""
            ok.runModal()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc func openBookmark(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        keyWindow?.activePanel.navigate(toFile: URL(fileURLWithPath: path))
    }

    // MARK: - Menu validation

    /// 正在文本框中输入时,让 ⌘C / ⌘V / ⌘A / ⌘⌫ 等按键回到文本框,
    /// 而不是触发文件操作。
    private var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }
        guard isEditingText else { return true }
        let editingSensitive: [Selector] = [
            #selector(menuCopy), #selector(menuPaste), #selector(menuSelectAll),
            #selector(menuMove), #selector(menuDelete), #selector(menuRename),
            #selector(menuGoBack), #selector(menuGoForward), #selector(menuGoUp),
            #selector(menuOpenSelection), #selector(menuAdd), #selector(menuExtract),
            #selector(menuTest), #selector(menuQuickCompress), #selector(menuQuickExtract),
            #selector(menuNewFolder), #selector(menuRefresh), #selector(menuInvertSelection),
        ]
        return !editingSensitive.contains(action)
    }

    // MARK: - Menu bar (7-Zip style)

    private func mi(_ title: String, _ action: Selector, _ key: String = "",
                    modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = modifiers
        i.target = self
        return i
    }

    /// 标准编辑命令(复制 / 粘贴 / 全选)走响应者链:
    /// 文本框里操作文本,文件列表里操作文件。
    private func standardEditItem(_ title: String, _ action: Selector,
                                  _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = .command
        i.target = nil
        return i
    }

    /// 生成功能键(方向键 / F1…F12)的 key equivalent。
    private func functionKey(_ code: Int) -> String {
        guard let scalar = UnicodeScalar(UInt32(code)) else { return "" }
        return String(Character(scalar))
    }

    func buildMenu() -> NSMenu {
        shortcutEntries.removeAll()
        let appMenu = NSMenu(title: "BingZip")
        appMenu.addItem(mi("关于 BingZip(版本信息)", #selector(menuAbout)))
        appMenu.addItem(.separator())
        appMenu.addItem(mi("设置…", #selector(menuSettings), ","))
        appMenu.addItem(mi("权限设置…", #selector(menuPermissions)))
        appMenu.addItem(.separator())
        let hideItem = mi("隐藏 BingZip", #selector(NSApplication.hide(_:)), "h")
        hideItem.target = NSApp
        appMenu.addItem(hideItem)
        let quitItem = mi("退出 BingZip", #selector(NSApplication.terminate(_:)), "q")
        quitItem.target = NSApp
        appMenu.addItem(quitItem)
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)

        let file = NSMenu(title: "文件")
        file.addItem(mi("新建窗口", #selector(menuNewWindow), "n"))
        let openArchiveItem = mi("打开压缩包…", #selector(menuOpenArchive), "o")
        registerShortcut(openArchiveItem)
        file.addItem(openArchiveItem)
        file.addItem(.separator())
        let addItem = mi("压缩…", #selector(menuAdd), "A")
        registerShortcut(addItem)
        file.addItem(addItem)
        let quickCompressItem = mi("快速压缩为 7z", #selector(menuQuickCompress), "C")
        registerShortcut(quickCompressItem)
        file.addItem(quickCompressItem)
        let extractItem = mi("解压…", #selector(menuExtract), "e")
        registerShortcut(extractItem)
        file.addItem(extractItem)
        let quickExtractItem = mi("快速解压到文件夹", #selector(menuQuickExtract), "E")
        registerShortcut(quickExtractItem)
        file.addItem(quickExtractItem)
        let testItem = mi("测试压缩包", #selector(menuTest), "t")
        registerShortcut(testItem)
        file.addItem(testItem)
        file.addItem(.separator())
        let newFolderItem = mi("新建文件夹", #selector(menuNewFolder), "N")
        registerShortcut(newFolderItem)
        file.addItem(newFolderItem)
        let deleteItem = mi("删除", #selector(menuDelete), "\u{8}")
        registerShortcut(deleteItem)
        file.addItem(deleteItem)
        let renameItem = mi("重命名", #selector(menuRename),
                            functionKey(NSF2FunctionKey), modifiers: [])
        registerShortcut(renameItem)
        file.addItem(renameItem)
        file.addItem(.separator())
        let propertiesItem = mi("属性…", #selector(menuProperties), "i")
        registerShortcut(propertiesItem)
        file.addItem(propertiesItem)
        file.addItem(mi("关闭窗口", #selector(menuClose), "w"))

        let edit = NSMenu(title: "编辑")
        edit.addItem(standardEditItem("复制", #selector(NSText.copy(_:)), "c"))
        edit.addItem(standardEditItem("粘贴", #selector(NSText.paste(_:)), "v"))
        edit.addItem(mi("移动", #selector(menuMove)))
        edit.addItem(.separator())
        edit.addItem(standardEditItem("全选", #selector(NSText.selectAll(_:)), "a"))
        edit.addItem(mi("反向选择", #selector(menuInvertSelection)))

        let go = NSMenu(title: "转到")
        let backItem = mi("后退", #selector(menuGoBack), "[")
        registerShortcut(backItem)
        go.addItem(backItem)
        let forwardItem = mi("前进", #selector(menuGoForward), "]")
        registerShortcut(forwardItem)
        go.addItem(forwardItem)
        go.addItem(.separator())
        let upItem = mi("上一级", #selector(menuGoUp), functionKey(NSUpArrowFunctionKey))
        registerShortcut(upItem)
        go.addItem(upItem)
        let openSelItem = mi("打开所选项目", #selector(menuOpenSelection),
                             functionKey(NSDownArrowFunctionKey))
        registerShortcut(openSelItem)
        go.addItem(openSelItem)

        let find = NSMenu(title: "查找")
        let findItem = mi("查找文件…", #selector(menuFind), "f")
        registerShortcut(findItem)
        find.addItem(findItem)
        find.addItem(mi("清除筛选", #selector(menuClearFilter)))

        let options = NSMenu(title: "选项")
        options.addItem(mi("设置…", #selector(menuSettings)))
        options.addItem(mi("代码页…", #selector(menuCodePage)))
        options.addItem(.separator())
        options.addItem(mi("安装命令行工具…", #selector(menuInstallCLI)))

        let view = NSMenu(title: "视图")
        let refreshItem = mi("刷新", #selector(menuRefresh), "r")
        registerShortcut(refreshItem)
        view.addItem(refreshItem)
        let treeItem = mi("显示目录树", #selector(menuToggleTree))
        treeItem.state = (UserDefaults.standard.object(forKey: "BingZipShowTree") as? Bool ?? true) ? .on : .off
        view.addItem(treeItem)

        let fav = NSMenu(title: "收藏夹")
        fav.addItem(mi("添加当前文件夹", #selector(menuAddBookmark)))
        let bookmarks = UserDefaults.standard.stringArray(forKey: "BingZipBookmarks") ?? []
        if !bookmarks.isEmpty { fav.addItem(.separator()) }
        for b in bookmarks {
            let i = NSMenuItem(title: "📁 \(b)", action: #selector(openBookmark(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = b
            fav.addItem(i)
        }

        let tools = NSMenu(title: "工具")
        tools.addItem(mi("基准测试…", #selector(menuBench)))
        tools.addItem(mi("计算 CRC/哈希…", #selector(menuHash)))
        tools.addItem(mi("后台任务…", #selector(menuBackgroundTasks)))

        let help = NSMenu(title: "帮助")
        help.addItem(mi("支持的格式…", #selector(menuFormats)))
        help.addItem(mi("权限设置…", #selector(menuPermissions)))
        help.addItem(.separator())
        help.addItem(mi("打开日志文件夹", #selector(menuOpenLogs)))
        help.addItem(mi("导出日志…", #selector(menuExportLogs)))
        help.addItem(mi("完全清除所有日志…", #selector(menuClearLogs)))
        help.addItem(.separator())
        help.addItem(mi("个人网站 (\(AppInfo.websiteDisplay))", #selector(menuWebsite)))
        help.addItem(mi("查看版本信息…", #selector(menuAbout)))

        for m in [file, edit, go, find, options, view, fav, tools, help] {
            let item = NSMenuItem()
            item.submenu = m
            mainMenu.addItem(item)
        }
        // 菜单可能在文本框编辑或对话框显示期间重建,保持挂起状态。
        if shortcutsSuspended {
            for entry in shortcutEntries {
                entry.item.keyEquivalent = ""
                entry.item.keyEquivalentModifierMask = []
            }
        }
        return mainMenu
    }
}