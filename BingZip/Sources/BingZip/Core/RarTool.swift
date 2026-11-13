import Foundation

/// RAR creation helper.
///
/// 7-Zip can only *extract* RAR archives (RAR is a proprietary format), so
/// creating `.rar` files requires RARLAB's official `rar` command line tool.
/// BingZip looks for that tool in the app bundle, common install locations and
/// `$PATH`, and lets the user pick it explicitly in Settings.
final class RarTool {

    static let shared = RarTool()

    /// UserDefaults key storing a manually selected `rar` executable.
    static let customPathKey = "BingZipRarPath"

    private(set) var binaryURL: URL?

    private init() {
        binaryURL = RarTool.locateBinary()
    }

    var isAvailable: Bool {
        guard let url = binaryURL else { return false }
        return RarTool.isExecutableFile(url)
    }

    /// Re-scan all locations (needed after the user installs the tool).
    func reload() {
        binaryURL = RarTool.locateBinary()
    }

    /// Store a user-selected `rar` executable, or clear it with `nil`.
    @discardableResult
    func setCustomBinary(_ url: URL?) -> Bool {
        if let url = url {
            guard RarTool.isExecutableFile(url) else {
                return false
            }
            UserDefaults.standard.set(url.path, forKey: Self.customPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.customPathKey)
        }
        reload()
        return isAvailable
    }

    private static func locateBinary() -> URL? {
        var candidates: [URL] = []

        // 0) Explicit choice saved from Settings
        if let saved = UserDefaults.standard.string(forKey: customPathKey), !saved.isEmpty {
            candidates.append(URL(fileURLWithPath: saved))
        }
        // 1) Environment override (useful for tests / portable installs)
        if let env = ProcessInfo.processInfo.environment["BINGZIP_RAR"], !env.isEmpty {
            candidates.append(URL(fileURLWithPath: env))
        }
        // 2) Next to the BingZip executable / in Bundle Resources
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        candidates.append(exeDir.appendingPathComponent("rar"))
        if let resURL = Bundle.main.resourceURL {
            candidates.append(resURL.appendingPathComponent("rar"))
        }
        // 3) Repo build output (development runs)
        let fp = #filePath
        if fp.hasPrefix("/") {
            let repoRoot = URL(fileURLWithPath: fp)
                .deletingLastPathComponent()   // Core
                .deletingLastPathComponent()   // BingZip (module)
                .deletingLastPathComponent()   // Sources
                .deletingLastPathComponent()   // BingZip project
                .deletingLastPathComponent()   // repo root
            candidates.append(repoRoot.appendingPathComponent("BingZip/dist/tools/rar"))
            candidates.append(repoRoot.appendingPathComponent("BingZip/Resources/rar"))
        }
        // 4) Walk up from the executable looking for dist/tools/rar
        var dir = exeDir
        for _ in 0..<7 {
            candidates.append(dir.appendingPathComponent("dist/tools/rar"))
            candidates.append(dir.appendingPathComponent("tools/rar"))
            dir = dir.deletingLastPathComponent()
        }
        // 5) Directories listed in PATH
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for component in path.split(separator: ":") where !component.isEmpty {
                candidates.append(URL(fileURLWithPath: String(component)).appendingPathComponent("rar"))
            }
        }
        // 6) Common install locations
        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/usr/local/bin/rar"),
            URL(fileURLWithPath: "/opt/homebrew/bin/rar"),
            URL(fileURLWithPath: "/Applications/rar/rar"),
            URL(fileURLWithPath: "/Applications/RAR/rar"),
            URL(fileURLWithPath: NSHomeDirectory() + "/.local/bin/rar"),
            URL(fileURLWithPath: NSHomeDirectory() + "/Applications/rar/rar"),
        ])

        for c in candidates where isExecutableFile(c) {
            return c
        }
        return nil
    }

    private static func isExecutableFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    // MARK: - Command line

    struct AddRequest {
        var archivePath: URL
        var files: [URL]
        var level: Int
        var password: String?
        var encryptHeader: Bool
        var volume: String?
        var deleteSource: Bool
        var storeSymlinks: Bool
        var excludes: [String]
        var threads: Int?
        var dictSize: String?
        var extraParams: String
    }

    struct Invocation {
        var executable: URL
        var args: [String]
        var workingDirectory: URL
    }

    enum RarError: LocalizedError {
        case notInstalled
        case noFiles

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "未找到 RARLAB 的 rar 工具。RAR 是专有格式,7-Zip 引擎只能解压 RAR;请安装 rar 工具后再试。"
            case .noFiles:
                return "没有选择要压缩的文件。"
            }
        }
    }

    /// Build the `rar a ...` invocation. Source paths are passed relative to a
    /// common working directory so archives do not contain absolute paths.
    func makeAddInvocation(_ request: AddRequest) throws -> Invocation {
        guard let executable = binaryURL, isAvailable else {
            throw RarError.notInstalled
        }
        guard !request.files.isEmpty else {
            throw RarError.noFiles
        }

        let base = Self.commonDirectory(of: request.files)
        let relativeFiles = request.files.map { Self.relativePath(of: $0, to: base) }

        var args = ["a", "-y", "-ma5", "-r"]
        args.append("-m\(Self.compressionLevel(for: request.level))")
        if let dict = request.dictSize, let normalized = Self.dictionarySize(dict) {
            args.append("-md\(normalized)")
        }
        if let threads = request.threads, threads > 0 {
            args.append("-mt\(threads)")
        }
        if let pw = request.password, !pw.isEmpty {
            // -hp also encrypts RAR headers (file names); -p encrypts data only.
            args.append(request.encryptHeader ? "-hp\(pw)" : "-p\(pw)")
        }
        if let volume = request.volume, !volume.isEmpty {
            args.append("-v\(volume)")
        }
        if request.deleteSource { args.append("-df") }
        if request.storeSymlinks { args.append("-ol") }
        for pattern in request.excludes where !pattern.isEmpty {
            args.append("-x\(pattern)")
        }
        let extra = request.extraParams.trimmingCharacters(in: .whitespaces)
        if !extra.isEmpty {
            args.append(contentsOf: extra.split(separator: " ").map(String.init))
        }
        args.append(request.archivePath.path)
        args.append(contentsOf: relativeFiles)

        return Invocation(executable: executable, args: args, workingDirectory: base)
    }

    /// Map BingZip/7-Zip levels (0,1,3,5,7,9) to RAR's -m0...-m5.
    static func compressionLevel(for level: Int) -> Int {
        switch level {
        case 0: return 0
        case 1: return 1
        case 2, 3: return 2
        case 4, 5: return 3
        case 6, 7: return 4
        default: return 5
        }
    }

    /// Normalize 7-Zip dictionary sizes (64k ... 1g) to values RAR accepts.
    static func dictionarySize(_ raw: String) -> String? {
        let s = raw.lowercased()
        guard let suffix = s.last, let value = Double(s.dropLast()) else { return nil }
        let bytes: Double
        switch suffix {
        case "k": bytes = value * 1024
        case "m": bytes = value * 1024 * 1024
        case "g": bytes = value * 1024 * 1024 * 1024
        default: return nil
        }
        let minimum = 128.0 * 1024
        let maximum = 1024.0 * 1024 * 1024
        let clamped = min(max(bytes, minimum), maximum)
        if clamped >= 1024 * 1024 {
            return "\(Int(clamped / (1024 * 1024)))m"
        }
        return "\(Int(clamped / 1024))k"
    }

    // MARK: - Path helpers

    static func commonDirectory(of files: [URL]) -> URL {
        guard var components = files.first?.deletingLastPathComponent().pathComponents else {
            return URL(fileURLWithPath: "/")
        }
        for file in files.dropFirst() {
            let other = file.deletingLastPathComponent().pathComponents
            var count = 0
            while count < components.count, count < other.count,
                  components[count] == other[count] {
                count += 1
            }
            components = Array(components.prefix(count))
        }
        var path = components.joined(separator: "/")
        if path.hasPrefix("//") { path.removeFirst() }
        return URL(fileURLWithPath: path.isEmpty ? "/" : path)
    }

    static func relativePath(of file: URL, to base: URL) -> String {
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        if file.path.hasPrefix(basePath) {
            return String(file.path.dropFirst(basePath.count))
        }
        return file.lastPathComponent
    }
}
