import AppKit
import FinderSync

/// Helpers for the embedded Finder Sync extension (即 Finder 右键菜单).
///
/// The extension lives in `BingZip.app/Contents/PlugIns/BingZipFinder.appex`
/// and provides two menu items:
///   • 压缩到压缩包  → `bingzip://compress?path=…`
///   • 打开压缩包    → `bingzip://open?path=…`
///
/// macOS only exposes Finder extensions after the user enables them, so this
/// type also reports the current state, registers the bundled extension with
/// PlugInKit and walks the user through enabling it on first launch.
enum FinderIntegration {

    static let extensionBundleID = "com.bingzip.app.finder"
    static let extensionDisplayName = "BingZip 右键菜单"
    static let compressTitle = "压缩到压缩包"
    static let openTitle = "打开压缩包"

    /// UserDefaults key: check the Finder menu at every launch (default true).
    static let startupCheckKey = "BingZipCheckFinderMenuAtLaunch"
    /// Environment override used by tests / development builds.
    static let skipCheckEnvironmentKey = "BINGZIP_SKIP_FINDER_CHECK"

    // MARK: - State

    /// The .appex shipped inside the running app bundle.
    static var extensionURL: URL? {
        guard let plugins = Bundle.main.builtInPlugInsURL else { return nil }
        let url = plugins.appendingPathComponent("BingZipFinder.appex", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Whether this app contains the Finder extension at all. Debug builds run
    /// directly from `.build` and therefore have no plug-in to check.
    static var isBundled: Bool { extensionURL != nil }

    /// Whether macOS currently has the Finder extension enabled.
    static var isEnabled: Bool {
        if FIFinderSyncController.isExtensionEnabled { return true }
        return isEnabledInPlugInKit()
    }

    static var isStartupCheckEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: startupCheckKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: startupCheckKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: startupCheckKey) }
    }

    /// Short human readable state for the About / Settings dialogs.
    static var statusText: String {
        guard isBundled else { return "未捆绑(开发版)" }
        return isEnabled ? "已启用 · \(compressTitle) / \(openTitle)" : "未启用"
    }

    // MARK: - Registration

    /// Register the bundled .appex with PlugInKit. Safe to call repeatedly.
    @discardableResult
    static func register() -> Bool {
        guard let url = extensionURL else { return false }
        _ = runPlugInKit(["-a", url.path])
        return true
    }

    /// Ask PlugInKit to enable the extension without leaving the app.
    /// Returns whether macOS reports the extension as enabled afterwards.
    @discardableResult
    static func enable() -> Bool {
        guard register() else { return false }
        _ = runPlugInKit(["-e", "use", "-i", extensionBundleID])
        for _ in 0..<10 {
            if isEnabled { return true }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return isEnabled
    }

    /// Open System Settings → Extensions so the user can toggle the extension.
    static func openSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    // MARK: - User facing checks

    /// Startup check: if the extension is disabled, explain what it does and
    /// offer a one-click enable. Respects the suppression checkbox and can be
    /// disabled permanently from Settings.
    static func checkAtLaunch() {
        guard ProcessInfo.processInfo.environment[skipCheckEnvironmentKey] != "1" else { return }
        guard isStartupCheckEnabled else { return }
        guard isBundled else {
            AppLogger.shared.log("Finder menu: extension not bundled (development build)")
            return
        }
        // Always refresh the registered path, so moving BingZip.app does not
        // leave PlugInKit pointing at an old location.
        register()
        if isEnabled {
            AppLogger.shared.log("Finder menu: extension enabled")
            return
        }

        AppLogger.shared.log("Finder menu: extension disabled, prompting user")

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "启用系统右键菜单?"
        alert.informativeText = """
        BingZip 已内置 Finder 右键菜单扩展。启用后,在 Finder 中右键选中文件即可看到:

          • \(compressTitle) — 打开压缩对话框
          • \(openTitle) — 在 BingZip 中浏览压缩包(仅对压缩包显示)

        点击“一键启用”即可。如果系统仍未显示,请在
        “系统设置 → 通用 → 登录项与扩展 → 访达扩展”中打开“\(extensionDisplayName)”。
        """
        alert.addButton(withTitle: "一键启用")
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "启动时不再检查"

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            isStartupCheckEnabled = false
            AppLogger.shared.log("Finder menu: startup check disabled by user")
        }

        switch response {
        case .alertFirstButtonReturn:
            if enable() {
                AppLogger.shared.log("Finder menu: enabled via PlugInKit")
            } else {
                AppLogger.shared.log("Finder menu: PlugInKit enable failed, opening settings")
                openSettings()
                showManualEnableHint()
            }
        case .alertSecondButtonReturn:
            openSettings()
        default:
            AppLogger.shared.log("Finder menu: user postponed enabling")
        }
    }

    /// Manual check used by the permissions dialog, About and Settings.
    @discardableResult
    static func checkAndOfferFix(quietIfEnabled: Bool = false) -> Bool {
        guard isBundled else {
            let alert = NSAlert()
            alert.messageText = "右键菜单未安装"
            alert.informativeText = """
            当前运行的 BingZip 没有内置 Finder 扩展(开发版)。
            请使用 dist/BingZip.app 运行完整版本。
            """
            alert.addButton(withTitle: "好")
            alert.runModal()
            return false
        }

        register()

        if isEnabled {
            if !quietIfEnabled {
                let alert = NSAlert()
                alert.messageText = "右键菜单已启用"
                alert.informativeText = """
                在 Finder 中右键选中文件时,可以看到:

                  • \(compressTitle)
                  • \(openTitle)(仅对压缩包显示)
                """
                alert.addButton(withTitle: "好")
                alert.runModal()
            }
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "右键菜单尚未启用"
        alert.informativeText = """
        在 Finder 中选中文件后,右键菜单需要显示“\(compressTitle)”和“\(openTitle)”。

        请启用“\(extensionDisplayName)”扩展。点击“一键启用”后,
        如果 Finder 中仍未出现,请到
        “系统设置 → 通用 → 登录项与扩展 → 访达扩展”中手动打开。
        """
        alert.addButton(withTitle: "一键启用")
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if enable() {
                let done = NSAlert()
                done.messageText = "右键菜单已启用"
                done.informativeText = "现在可以在 Finder 中右键使用“\(compressTitle)”和“\(openTitle)”。"
                done.addButton(withTitle: "好")
                done.runModal()
                return true
            }
            openSettings()
            showManualEnableHint()
            return false
        case .alertSecondButtonReturn:
            openSettings()
            return false
        default:
            return false
        }
    }

    private static func showManualEnableHint() {
        let alert = NSAlert()
        alert.messageText = "请手动启用右键菜单"
        alert.informativeText = """
        请在“系统设置 → 通用 → 登录项与扩展 → 访达扩展”中
        打开“\(extensionDisplayName)”。

        启用后无需重启应用,重新在 Finder 中右键即可看到两个菜单项。
        """
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - PlugInKit

    private static func isEnabledInPlugInKit() -> Bool {
        guard let output = runPlugInKit(["-m", "-i", extensionBundleID]) else { return false }
        return output.split(separator: "\n").contains { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            return text.hasPrefix("+") && text.contains(extensionBundleID)
        }
    }

    @discardableResult
    private static func runPlugInKit(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            AppLogger.shared.log("Finder menu: pluginkit failed: \(error.localizedDescription)")
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
