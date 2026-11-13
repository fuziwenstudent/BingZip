import Foundation

/// Wrapper around the bundled 7zz executable (built from the 7-Zip 26.05 sources).
/// All GUI features are powered by this engine.
final class SevenZip {

    static let shared = SevenZip()

    private(set) var binaryURL: URL

    private init() {
        binaryURL = SevenZip.locateBinary()
    }

    private static func locateBinary() -> URL {
        var candidates: [URL] = []
        // 0) Explicit override (useful for tests / custom builds)
        if let env = ProcessInfo.processInfo.environment["BINGZIP_7ZZ"],
           FileManager.default.isExecutableFile(atPath: env) {
            return URL(fileURLWithPath: env)
        }
        // 1) Next to the BingZip executable (BingZip.app/Contents/MacOS/7zz)
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        candidates.append(exeDir.appendingPathComponent("7zz"))
        // 2) Bundle Resources
        if let resURL = Bundle.main.resourceURL {
            candidates.append(resURL.appendingPathComponent("7zz"))
        }
        // 3) Repo build output. #filePath can be relative depending on how the
        //    compiler was invoked, so only use it when it is absolute.
        let fp = #filePath
        if fp.hasPrefix("/") {
            let repoRoot = URL(fileURLWithPath: fp)
                .deletingLastPathComponent()   // Core
                .deletingLastPathComponent()   // BingZip (module)
                .deletingLastPathComponent()   // Sources
                .deletingLastPathComponent()   // BingZip project
                .deletingLastPathComponent()   // repo root
            candidates.append(repoRoot.appendingPathComponent("CPP/7zip/Bundles/Alone2/b/m_arm64/7zz"))
        }
        // 4) Walk up from the executable looking for the build tree
        var dir = exeDir
        for _ in 0..<7 {
            candidates.append(dir.appendingPathComponent("CPP/7zip/Bundles/Alone2/b/m_arm64/7zz"))
            dir = dir.deletingLastPathComponent()
        }
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/7zz"))
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/7zz"))

        for c in candidates where FileManager.default.isExecutableFile(atPath: c.path) {
            return c
        }
        return URL(fileURLWithPath: "/usr/local/bin/7zz")
    }

    // MARK: - Low level run

    struct RunResult {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    /// Runs 7zz synchronously on the calling thread. `onProcess` receives the
    /// launched process (for cancellation). `onLine` is called on a background
    /// queue for each progress line (7zz writes progress to stderr).
    /// `executable` lets callers run a compatible tool (e.g. RARLAB `rar`);
    /// `workingDirectory` controls how relative paths are stored;
    /// `streamStdout` also forwards stdout lines to `onLine` (RAR prints there).
    func run(_ args: [String],
             executable: URL? = nil,
             workingDirectory: URL? = nil,
             streamStdout: Bool = false,
             onProcess: ((Process) -> Void)? = nil,
             onLine: ((String) -> Void)? = nil) throws -> RunResult {
        let p = Process()
        p.executableURL = executable ?? binaryURL
        p.arguments = args
        p.environment = ProcessInfo.processInfo.environment
        if let workingDirectory = workingDirectory {
            p.currentDirectoryURL = workingDirectory
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        // Never let 7zz block waiting for interactive input (e.g. password prompt).
        p.standardInput = FileHandle.nullDevice

        var stdoutData = Data()
        var stderrData = Data()
        let lock = NSLock()
        let outQ = DispatchQueue(label: "bingzip.out")

        outPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil }
            else {
                outQ.async { lock.lock(); stdoutData.append(d); lock.unlock() }
                if streamStdout, let onLine = onLine {
                    let s = String(data: d, encoding: .utf8) ?? ""
                    for piece in s.split(whereSeparator: { $0 == "\r" || $0 == "\n" || $0 == "\u{08}" }) {
                        let l = String(piece).trimmingCharacters(in: .whitespaces)
                        if !l.isEmpty { onLine(l) }
                    }
                }
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil }
            else {
                lock.lock(); stderrData.append(d); lock.unlock()
                if let onLine = onLine {
                    let s = String(data: d, encoding: .utf8) ?? ""
                    // 7zz refreshes progress with '\r' and backspaces ('\b'); treat all as separators
                    for piece in s.split(whereSeparator: { $0 == "\r" || $0 == "\n" || $0 == "\u{08}" }) {
                        let l = String(piece).trimmingCharacters(in: .whitespaces)
                        if !l.isEmpty { onLine(l) }
                    }
                }
            }
        }

        try p.run()
        onProcess?(p)
        p.waitUntilExit()

        lock.lock()
        let outStr = String(data: stdoutData, encoding: .utf8) ?? ""
        let errStr = String(data: stderrData, encoding: .utf8) ?? ""
        lock.unlock()

        return RunResult(exitCode: p.terminationStatus, stdout: outStr, stderr: errStr)
    }

    /// Async variant, result delivered on main thread.
    func runAsync(_ args: [String],
                  onLine: ((String) -> Void)? = nil,
                  completion: @escaping (Result<RunResult, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let r = try self.run(args, onLine: onLine)
                DispatchQueue.main.async { completion(.success(r)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Listing

    func list(archive: URL, password: String?) throws -> ArchiveListing {
        var args = ["l", "-slt", "-ba"]
        // Always pass -p: an empty -p means "empty password" and prevents
        // 7zz from prompting on stdin for encrypted headers.
        if let pw = password, !pw.isEmpty {
            args.append("-p\(pw)")
        } else {
            args.append("-p")
        }
        args.append(archive.path)
        let r = try run(args)

        var listing = ArchiveListing()
        var current: [String: String] = [:]

        func flush() {
            guard !current.isEmpty else { return }
            // A block containing "Type" and "Physical Size" (but no Size) is the
            // archive description, not a file entry.
            let isArchiveInfo = current["Type"] != nil && current["Physical Size"] != nil
            if isArchiveInfo {
                for (k, v) in current where k != "Path" {
                    listing.info.append((k, v))
                }
            } else if let e = makeEntry(current) {
                listing.entries.append(e)
            }
            current = [:]
        }

        for rawLine in r.stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line == "--" || line == "----------" {
                flush()
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let val = parts[1].trimmingCharacters(in: .whitespaces)
            current[key] = val
        }
        flush()
        return listing
    }

    private func makeEntry(_ dict: [String: String]) -> ArchiveEntry? {
        guard let path = dict["Path"], !path.isEmpty else { return nil }
        let attrs = dict["Attributes"] ?? ""
        var isDir = false
        if path.hasSuffix("/") && path.count > 1 { isDir = true }
        if attrs.contains("D") { isDir = true }
        if (dict["Folder"] ?? "-") == "+" { isDir = true }
        var date: Date? = nil
        let raw = dict["Modified"] ?? ""
        if !raw.isEmpty {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let trimmedDate = raw.split(separator: ".").first.map(String.init) ?? raw
            date = df.date(from: trimmedDate)
        }
        return ArchiveEntry(
            path: path,
            isDirectory: isDir,
            size: Int64(dict["Size"] ?? "") ?? 0,
            packedSize: Int64(dict["Packed Size"] ?? "") ?? 0,
            modified: date,
            attributes: attrs,
            crc: dict["CRC"] ?? "",
            encrypted: (dict["Encrypted"] ?? "-") == "+",
            method: dict["Method"] ?? ""
        )
    }

    // MARK: - Progress parsing

    static func parseProgress(_ line: String) -> ProgressInfo? {
        var info = ProgressInfo(rawLine: line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("Everything is Ok") { return nil }
        if let r = trimmed.range(of: #"^\s*(\d+)%"#, options: .regularExpression) {
            let pctStr = trimmed[r].trimmingCharacters(in: .whitespaces)
            let pct = Double(pctStr.dropLast())
            if let p = pct { info.percent = p }
            info.extra = String(trimmed[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            return info
        }
        return nil
    }
}