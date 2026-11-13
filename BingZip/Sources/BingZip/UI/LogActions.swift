import AppKit

/// Shared export / clear actions for the log directory. Used by the version
/// dialog, Settings and the Help menu.
enum LogActions {

    /// Ask for a destination and export every log file as a ZIP archive.
    /// Returns the archive URL on success.
    @discardableResult
    static func export(from window: NSWindow? = nil) -> URL? {
        let files = AppLogger.shared.logFiles()
        guard !files.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "没有可导出的日志"
            alert.informativeText = "当前日志文件夹是空的。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            return nil
        }

        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let panel = NSSavePanel()
        panel.message = "导出全部运行日志与崩溃日志"
        panel.nameFieldStringValue = "BingZip-日志-\(df.string(from: Date())).zip"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, var url = panel.url else { return nil }
        if url.pathExtension.lowercased() != "zip" {
            url = url.appendingPathExtension("zip")
        }

        do {
            try AppLogger.shared.exportAllLogs(to: url)
            let done = NSAlert()
            done.messageText = "日志已导出"
            done.informativeText = "已把 \(files.count) 个日志文件导出到:\n\(url.path)"
            done.addButton(withTitle: "在 Finder 中显示")
            done.addButton(withTitle: "好")
            if done.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            return url
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    /// Ask for confirmation, then permanently delete every log file.
    @discardableResult
    static func clearAll(from window: NSWindow? = nil) -> Bool {
        let files = AppLogger.shared.logFiles()
        let crashCount = files.filter { $0.isCrash }.count
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "完全清除所有日志?"
        if files.isEmpty {
            alert.informativeText = "当前日志文件夹已经是空的。"
        } else {
            alert.informativeText = """
            将永久删除 \(files.count) 个日志文件(其中崩溃日志 \(crashCount) 个),
            包括运行日志和崩溃日志。此操作不可撤销。
            """
        }
        alert.addButton(withTitle: "完全清除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        if files.isEmpty { return true }

        do {
            try AppLogger.shared.clearAllLogs()
            let done = NSAlert()
            done.messageText = "日志已完全清除"
            done.informativeText = "已删除 \(files.count) 个日志文件。"
            done.addButton(withTitle: "好")
            done.runModal()
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }
}
