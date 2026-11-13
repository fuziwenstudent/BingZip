import Foundation

// MARK: - Archive Entry (one item inside an archive listing from `7zz l -slt`)

struct ArchiveEntry {
    var path: String          // full path inside archive, uses "/" separators, no leading slash
    var isDirectory: Bool
    var size: Int64
    var packedSize: Int64
    var modified: Date?
    var attributes: String
    var crc: String
    var encrypted: Bool
    var method: String

    var name: String {
        let p = path.hasSuffix("/") ? String(path.dropLast()) : path
        return (p as NSString).lastPathComponent
    }
}

// MARK: - Parsed listing result

struct ArchiveListing {
    var entries: [ArchiveEntry] = []
    /// key/value block describing the archive itself (Type, Physical Size, ...)
    var info: [(String, String)] = []

    var physicalSize: Int64 {
        guard let v = info.first(where: { $0.0 == "Physical Size" })?.1,
              let n = Int64(v) else { return 0 }
        return n
    }
}

// MARK: - Progress

struct ProgressInfo {
    var percent: Double?     // 0...100
    var currentFile: String = ""
    var extra: String = ""   // e.g. "1 file, 12 KB"
    var rawLine: String = ""
}

// MARK: - Archive format info

enum ArchiveFormat: String, CaseIterable {
    case sevenZ = "7z"
    case zip = "Zip"
    case tar = "Tar"
    case gzip = "GZip"
    case xz = "XZ"
    case bzip2 = "BZip2"
    case wim = "WIM"

    var defaultExtension: String {
        switch self {
        case .sevenZ: return "7z"
        case .zip: return "zip"
        case .tar: return "tar"
        case .gzip: return "gz"
        case .xz: return "xz"
        case .bzip2: return "bz2"
        case .wim: return "wim"
        }
    }
}

/// Well known archive extensions (case-insensitive)
let knownArchiveExtensions: Set<String> = [
    "7z", "zip", "rar", "tar", "gz", "tgz", "bz2", "xz", "txz", "lzma", "cab",
    "wim", "swm", "iso", "udf", "chm", "msi", "jar", "xar", "dmg", "hfs",
    "z", "taz", "lzh", "lha", "arj", "rpm", "deb", "cramfs", "squashfs", "lz4", "lz5", "sfs", "fat", "ntfs", "vhd", "appx"
]

func isKnownArchive(_ url: URL) -> Bool {
    let name = url.lastPathComponent.lowercased()
    if name.hasSuffix(".tar.gz") || name.hasSuffix(".tar.bz2") || name.hasSuffix(".tar.xz") { return true }
    let ext = url.pathExtension.lowercased()
    return knownArchiveExtensions.contains(ext)
}

// MARK: - Size formatting

func formatBytes(_ bytes: Int64) -> String {
    guard bytes >= 0 else { return "" }
    if bytes < 1024 { return "\(bytes) B" }
    let kb = Double(bytes) / 1024.0
    if kb < 1024 { return String(format: "%.1f KB", kb) }
    let mb = kb / 1024.0
    if mb < 1024 { return String(format: "%.1f MB", mb) }
    let gb = mb / 1024.0
    return String(format: "%.2f GB", gb)
}

func fileKindName(forName name: String, isDirectory: Bool) -> String {
    if isDirectory { return "文件夹 (Folder)" }
    let ext = (name as NSString).pathExtension.lowercased()
    switch ext {
    case "7z": return "7z 压缩文件"
    case "zip", "jar", "apk": return "Zip 压缩文件"
    case "rar": return "Rar 压缩文件"
    case "tar", "tgz", "tbz", "txz": return "Tar 归档"
    case "gz", "bz2", "xz", "lzma": return "压缩文件"
    case "txt", "log", "md": return "文本文件"
    case "png", "jpg", "jpeg", "gif", "bmp", "icns": return "图像文件"
    case "pdf": return "PDF 文档"
    case "app", "dmg", "pkg": return "应用程序"
    case "h", "hpp", "c", "cpp", "m", "mm", "swift", "py", "sh", "js": return "源代码文件"
    case "html", "htm", "css": return "网页文件"
    default: return ext.isEmpty ? "文件" : "\(ext.uppercased()) 文件"
    }
}