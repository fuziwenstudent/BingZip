import AppKit
import Darwin

/// Global logger + crash reporter.
/// Logs live in ~/Library/Logs/BingZip/:
///   - bingzip.log            (rolling operation log)
///   - crash-<session>-*.log  (uncaught exceptions / fatal signals)
final class AppLogger {

    static let shared = AppLogger()

    /// One file inside the log directory.
    struct LogFileInfo {
        let url: URL
        let size: Int64
        let modified: Date?

        var isCrash: Bool { url.lastPathComponent.hasPrefix("crash-") }
    }

    enum LogError: LocalizedError {
        case noLogs
        case destinationInsideLogs
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .noLogs:
                return "当前没有可导出的日志文件。"
            case .destinationInsideLogs:
                return "不能把日志压缩包保存在日志文件夹内部,请换一个位置。"
            case .exportFailed(let detail):
                return "导出日志失败:\(detail)"
            }
        }
    }

    let logDirectory: URL
    let sessionStamp: String
    private let logFile: URL
    private let queue = DispatchQueue(label: "com.bingzip.logger")
    private let df: DateFormatter

    private init() {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library")
        logDirectory = lib.appendingPathComponent("Logs/BingZip", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        logFile = logDirectory.appendingPathComponent("bingzip.log")
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        sessionStamp = f.string(from: Date())
        df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        rotateIfNeeded()
    }

    private func rotateIfNeeded() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: logFile.path)
        let size = (attrs?[.size] as? Int) ?? 0
        if size > 2 * 1024 * 1024 {
            let backup = logDirectory.appendingPathComponent("bingzip.log.1")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: logFile, to: backup)
        }
    }

    func log(_ message: String) {
        let stamp = df.string(from: Date())
        queue.async {
            self.append("\(stamp) \(message)\n")
        }
    }

    private func append(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: data)
            return
        }
        guard let fh = try? FileHandle(forWritingTo: logFile) else { return }
        defer { try? fh.close() }
        _ = try? fh.seekToEnd()
        try? fh.write(contentsOf: data)
    }

    // MARK: - Crash handlers

    func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let detail = """
            Exception: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "unknown")
            Stack:
            \(Thread.callStackSymbols.joined(separator: "\n"))
            """
            AppLogger.shared.writeCrash(kind: "exception", detail: detail)
        }
        for sig in [SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(sig) { s in
                AppLogger.writeSignalCrash(s)
            }
        }
        log("== BingZip session \(sessionStamp) started; macOS=\(ProcessInfo.processInfo.operatingSystemVersionString) ==")
    }

    func writeCrash(kind: String, detail: String) {
        let name = "crash-\(sessionStamp)-\(kind).log"
        let url = logDirectory.appendingPathComponent(name)
        let content = """
        BingZip Crash Report
        Session: \(sessionStamp)
        Time: \(Date())
        App: \(AppInfo.name) \(AppInfo.version)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Arch: \(archString())
        Engine: \(SevenZip.shared.binaryURL.path)
        ----------------------------------------
        \(detail)
        """
        try? content.write(to: url, atomically: true, encoding: .utf8)
        queue.sync { self.append("CRASH (\(kind)) written to \(url.path)\n") }
    }

    private func archString() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    /// Signal handler: POSIX-only writes, then restore default handler and re-raise.
    static func writeSignalCrash(_ sig: Int32) {
        let path = "\(AppLogger.shared.logDirectory.path)/crash-\(AppLogger.shared.sessionStamp)-signal-\(sig).log"
        let fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        if fd >= 0 {
            let header = "BingZip fatal signal \(sig)\n"
            header.withCString { _ = write(fd, $0, strlen($0)) }
            var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
            let n = backtrace(&frames, 64)
            backtrace_symbols_fd(&frames, n, fd)
            close(fd)
        }
        signal(sig, SIG_DFL)
        raise(sig)
    }

    // MARK: - Log files (export / clear)

    /// All files currently in the log directory, newest first.
    func logFiles() -> [LogFileInfo] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let urls = try? fm.contentsOfDirectory(at: logDirectory,
                                                     includingPropertiesForKeys: keys,
                                                     options: [.skipsHiddenFiles]) else {
            return []
        }
        return urls.compactMap { url -> LogFileInfo? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { return nil }
            return LogFileInfo(url: url,
                               size: Int64(values.fileSize ?? 0),
                               modified: values.contentModificationDate)
        }.sorted {
            ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast)
        }
    }

    /// Export every log file as a ZIP archive using the system `ditto` tool.
    /// The archive contains a top-level `BingZip` folder with all log files.
    func exportAllLogs(to destination: URL) throws {
        let files = logFiles()
        guard !files.isEmpty else { throw LogError.noLogs }

        let logPath = logDirectory.path.hasSuffix("/") ? logDirectory.path : logDirectory.path + "/"
        guard !destination.path.hasPrefix(logPath) else {
            throw LogError.destinationInsideLogs
        }
        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--keepParent", logDirectory.path, destination.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            throw LogError.exportFailed(error.localizedDescription)
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw LogError.exportFailed("ditto 退出码 \(p.terminationStatus)")
        }
    }

    /// Permanently delete every log file (operation log + crash logs).
    func clearAllLogs() throws {
        try queue.sync {
            let fm = FileManager.default
            let urls = try fm.contentsOfDirectory(at: logDirectory,
                                                  includingPropertiesForKeys: nil)
            for url in urls {
                try fm.removeItem(at: url)
            }
        }
    }

    // MARK: - Helpers

    /// Hide passwords before writing command lines to the log.
    /// `-p...` and RAR's `-hp...` (header encryption) are both redacted.
    func redactedArguments(_ args: [String]) -> String {
        args.map { arg in
            if arg.hasPrefix("-hp") { return "-hp***" }
            if arg.hasPrefix("-p") { return "-p***" }
            return arg
        }.joined(separator: " ")
    }
}