import Foundation

/// Command-line argument builders that mirror the 7-Zip GUI dialog options.
enum ArgsBuilder {

    /// Build `7zz a ...` arguments from Add-dialog settings.
    static func add(archivePath: URL,
                    files: [String],
                    format: String,            // 7z / zip / tar ...
                    level: Int,                // -mx : 0 store ... 9 ultra
                    method: String?,           // -m0=
                    dictSize: String?,         // -md=
                    wordSize: Int?,            // -mfb=
                    threads: Int?,             // -mmt=
                    solid: String?,            // -ms=on/off/size
                    password: String?,
                    encryptHeader: Bool,       // -mhe=on (7z only)
                    volume: String?,           // -v2m
                    updateMode: String,        // extra switches
                    pathMode: String,          // extra switches
                    extraParams: String) -> [String] {
        var args = ["a", "-y", "-bsp1", "-t\(format.lowercased())"]
        if level >= 0 { args.append("-mx=\(level)") }
        if let m = method, !m.isEmpty { args.append("-m0=\(m)") }
        if let d = dictSize, !d.isEmpty { args.append("-md=\(d)") }
        if let w = wordSize, w > 0 { args.append("-mfb=\(w)") }
        if let t = threads, t > 0 { args.append("-mmt=\(t)") }
        if let s = solid, !s.isEmpty { args.append("-ms=\(s)") }
        appendSwitches(updateMode, into: &args)
        appendSwitches(pathMode, into: &args)
        if let pw = password, !pw.isEmpty {
            args.append("-p\(pw)")
            if encryptHeader { args.append("-mhe=on") }
        }
        if let v = volume, !v.isEmpty { args.append("-v\(v)") }
        appendSwitches(extraParams, into: &args)
        args.append(archivePath.path)
        args.append(contentsOf: files)
        return args
    }

    /// Build `7zz x ...` / `7zz e ...` arguments from Extract-dialog settings.
    static func extract(archivePath: URL,
                        files: [String]?,
                        destDir: URL,
                        password: String?,
                        pathMode: String,       // -ep / -ep1 / -ep2 / -ep3
                        overwrite: String,      // -aoa / -aos / -aou / -aot
                        extraParams: String,
                        extractWithoutPaths: Bool) -> [String] {
        var args = [extractWithoutPaths ? "e" : "x", "-y", "-bsp1"]
        args.append("-o\(destDir.path)")
        if let pw = password, !pw.isEmpty { args.append("-p\(pw)") }
        if !overwrite.isEmpty { args.append(overwrite) }
        appendSwitches(pathMode, into: &args)
        appendSwitches(extraParams, into: &args)
        args.append(archivePath.path)
        if let files = files { args.append(contentsOf: files) }
        return args
    }

    private static func appendSwitches(_ s: String, into args: inout [String]) {
        let t = s.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { args.append(contentsOf: t.split(separator: " ").map(String.init)) }
    }

    // MARK: - Compression level mapping (7-Zip GUI levels)

    /// (label, -mx value) — 用普通用户能理解的说法
    static let levels: [(String, Int)] = [
        ("不压缩(仅打包)", 0),
        ("最快(文件最大)", 1),
        ("较快", 3),
        ("普通(推荐)", 5),
        ("更小", 7),
        ("最小(最慢)", 9)
    ]

    /// Methods per format
    static func methods(for format: String) -> [String] {
        switch format.lowercased() {
        case "7z": return ["LZMA2", "LZMA", "PPMd", "BZip2", "Deflate", "Copy"]
        case "zip": return ["Deflate", "Deflate64", "LZMA", "PPMd", "BZip2", "Copy"]
        case "rar": return ["RAR5"]
        case "xz", "gz", "gzip", "bz2", "bzip2", "tar", "wim": return ["Copy"]
        default: return ["LZMA2", "LZMA", "PPMd", "BZip2", "Deflate", "Copy"]
        }
    }

    /// 格式对应的文件扩展名(弹窗标题 "GZip" -> "gz", "BZip2" -> "bz2")
    static func fileExtension(for format: String) -> String {
        switch format.lowercased() {
        case "7z": return "7z"
        case "zip": return "zip"
        case "rar": return "rar"
        case "tar": return "tar"
        case "gzip", "gz": return "gz"
        case "xz": return "xz"
        case "bzip2", "bz2": return "bz2"
        case "wim": return "wim"
        default: return format.lowercased()
        }
    }

    /// Dictionary sizes per method
    static func dictSizes(for method: String?) -> [String] {
        switch method {
        case "LZMA2", "LZMA":
            return ["64k", "128k", "256k", "512k", "1m", "2m", "4m", "8m", "16m", "32m", "64m", "128m", "256m", "512m", "1g"]
        case "PPMd":
            return ["1m", "2m", "4m", "8m", "16m", "32m", "64m", "128m", "192m"]
        case "BZip2":
            return ["100k", "200k", "300k", "400k", "500k", "600k", "700k", "800k", "900k"]
        default:
            return []
        }
    }

    /// Approximate memory usage (like 7-Zip shows in its Add dialog)
    static func estimateMemory(method: String?, dictSize: String?, level: Int) -> String {
        guard let m = method, let d = dictSize, !d.isEmpty,
              m == "LZMA2" || m == "LZMA" || m == "PPMd" else { return "—" }
        var bytes: Double = 0
        let s = d.lowercased()
        let num = Double(s.dropLast()) ?? 0
        if s.hasSuffix("k") { bytes = num * 1024 }
        else if s.hasSuffix("m") { bytes = num * 1024 * 1024 }
        else if s.hasSuffix("g") { bytes = num * 1024 * 1024 * 1024 }
        else { bytes = num }
        let factor: Double
        switch m {
        case "LZMA2": factor = level >= 9 ? 24.0 : (level >= 7 ? 23.0 : (level >= 5 ? 22.0 : 12.0))
        case "LZMA": factor = level >= 9 ? 12.0 : (level >= 5 ? 11.5 : 10.5)
        default: factor = level >= 9 ? 3.0 : 1.5 // PPMd
        }
        let compr = bytes * factor
        let decompr = m == "PPMd" ? bytes : bytes + 2 * 1024 * 1024
        return "\(humanMem(compr)) / \(humanMem(decompr))"
    }

    private static func humanMem(_ b: Double) -> String {
        if b >= 1024 * 1024 * 1024 { return String(format: "%.1f GB", b / 1_073_741_824) }
        if b >= 1024 * 1024 { return String(format: "%.1f MB", b / 1_048_576) }
        if b >= 1024 { return String(format: "%.1f KB", b / 1024) }
        return String(format: "%.0f B", b)
    }
}