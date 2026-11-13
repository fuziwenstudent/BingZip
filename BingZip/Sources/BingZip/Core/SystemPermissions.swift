import AppKit

/// Full Disk Access detection result. macOS has no public API for this, so we
/// probe a TCC-protected file without triggering a prompt.
enum FullDiskAccessState {
    case granted
    case denied
    case unknown

    var title: String {
        switch self {
        case .granted: return "已开启"
        case .denied: return "未开启"
        case .unknown: return "无法检测"
        }
    }

    var logName: String {
        switch self {
        case .granted: return "granted"
        case .denied: return "denied"
        case .unknown: return "unknown"
        }
    }
}

/// Centralised macOS permission helpers.
///
/// macOS does not allow an app to grant TCC permissions by itself. The best we
/// can do is collect everything in one place:
///   • Finder Sync extension  → can be enabled through PlugInKit
///   • Full Disk Access       → one switch covers Desktop / Documents /
///                              Downloads / removable / network volumes
enum SystemPermissions {

    static let startupCheckKey = "BingZipCheckPermissionsAtLaunch"
    static let promptSuppressedKey = "BingZipPermissionPromptSuppressed"
    static let scanHintSuppressedKey = "BingZipScanFDAPromptSuppressed"
    static let skipCheckEnvironmentKey = "BINGZIP_SKIP_PERMISSION_CHECK"

    static var isStartupCheckEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: startupCheckKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: startupCheckKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: startupCheckKey) }
    }

    /// Best-effort Full Disk Access check. Reading TCC.db requires FDA and does
    /// not show a permission dialog when access is denied.
    static var fullDiskAccessState: FullDiskAccessState {
        let home = NSHomeDirectory()
        let candidates = [
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            home + "/Library/Safari/History.db",
            home + "/Library/Mail",
        ]
        for path in candidates {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                if (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil {
                    return .granted
                }
                return .denied
            }
            if let handle = FileHandle(forReadingAtPath: path) {
                handle.closeFile()
                return .granted
            }
            return .denied
        }
        return .unknown
    }

    /// Open System Settings → Privacy & Security → Full Disk Access.
    static func openFullDiskAccessSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ]
        for string in candidates {
            guard let url = URL(string: string) else { continue }
            if NSWorkspace.shared.open(url) {
                AppLogger.shared.log("Permissions: opened \(string)")
                return
            }
        }
        AppLogger.shared.log("Permissions: failed to open Full Disk Access settings")
    }

    /// Reveal BingZip.app in Finder so it can be dragged into the FDA list.
    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    // MARK: - Startup / scan prompts

    /// One consolidated startup prompt. Avoids two separate permission dialogs.
    static func checkAtLaunch(parent: NSWindow?) {
        guard ProcessInfo.processInfo.environment[skipCheckEnvironmentKey] != "1" else { return }
        guard isStartupCheckEnabled else { return }
        guard FinderIntegration.isBundled else { return }

        FinderIntegration.register()
        let finderEnabled = FinderIntegration.isEnabled
        let fda = fullDiskAccessState
        AppLogger.shared.log("Permissions: Finder menu=\(finderEnabled), Full Disk Access=\(fda.logName)")

        // "unknown" is not treated as missing: probing can fail on unusual setups.
        let missing = !finderEnabled || fda == .denied
        guard missing else { return }
        guard !UserDefaults.standard.bool(forKey: promptSuppressedKey) else { return }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "一次性完成权限设置"
        alert.informativeText = """
        为避免扫描、压缩、解压时逐个文件夹授权,建议在同一个窗口中完成以下两项:

          • Finder 右键菜单:\(finderEnabled ? "已启用" : "未启用")
          • 完全磁盘访问:\(fda.title)

        macOS 不允许应用自动授予敏感权限。打开权限设置后按提示操作一次,
        完全磁盘访问会同时覆盖桌面、文稿、下载、外接磁盘和网络卷。
        开启后请退出并重新启动 BingZip。
        """
        alert.addButton(withTitle: "打开权限设置")
        alert.addButton(withTitle: "稍后")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "启动时不再提示"

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: promptSuppressedKey)
            AppLogger.shared.log("Permissions: startup prompt suppressed")
        }
        if response == .alertFirstButtonReturn {
            PermissionsDialog().runModal(on: parent)
        }
    }

    /// Called by the scan action. If FDA is denied, offer one unified
    /// authorisation instead of letting macOS ask for each folder separately.
    /// Returns true when scanning should continue.
    static func confirmFullDiskAccessForScan(on parent: NSWindow?) -> Bool {
        guard fullDiskAccessState == .denied else { return true }
        guard !UserDefaults.standard.bool(forKey: scanHintSuppressedKey) else { return true }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "扫描前建议一次性授权"
        alert.informativeText = """
        扫描会递归读取当前文件夹。未开启完全磁盘访问时,macOS 可能逐个询问
        桌面、文稿、下载、外接磁盘和网络卷等目录。

        只需开启一次完全磁盘访问,后续扫描和压缩就不会再重复询问。
        """
        alert.addButton(withTitle: "打开权限设置")
        alert.addButton(withTitle: "仍然扫描")
        alert.addButton(withTitle: "取消")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "以后不再提醒"

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: scanHintSuppressedKey)
            AppLogger.shared.log("Permissions: scan FDA hint suppressed")
        }

        switch response {
        case .alertFirstButtonReturn:
            PermissionsDialog().runModal(on: parent)
            return fullDiskAccessState == .granted
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }
}

