import Foundation
import AppKit

// MARK: - Data loading helpers
extension FilePanel {

    static func children(of inner: String, in entries: [ArchiveEntry]) -> [PanelItem] {
        var result: [PanelItem] = []
        var addedDirs = Set<String>()
        let prefix = inner.isEmpty ? "" : inner + "/"
        for e in entries {
            var p = e.path
            if p.hasPrefix("./") { p = String(p.dropFirst(2)) }
            if !inner.isEmpty {
                guard p.hasPrefix(prefix) else { continue }
            }
            let rest = inner.isEmpty ? p : String(p.dropFirst(prefix.count))
            if rest.isEmpty { continue }
            if rest.contains("/") {
                let dir = rest.components(separatedBy: "/")[0]
                if addedDirs.insert(dir).inserted {
                    result.append(PanelItem(name: dir, isDirectory: true, size: 0, packedSize: 0,
                                            modified: nil, crc: "", attributes: "", fileURL: nil,
                                            archivePath: inner.isEmpty ? dir : inner + "/" + dir, isParent: false))
                }
            } else {
                // 目录实体可能已经由子路径推导插入过,避免重复
                if e.isDirectory {
                    if addedDirs.contains(e.name) { continue }
                    addedDirs.insert(e.name)
                }
                result.append(PanelItem(name: e.name, isDirectory: e.isDirectory, size: e.size,
                                        packedSize: e.packedSize, modified: e.modified, crc: e.crc,
                                        attributes: e.attributes, fileURL: nil, archivePath: e.path, isParent: false))
            }
        }
        result.insert(PanelItem(name: "..", isDirectory: true, size: 0, packedSize: 0, modified: nil,
                                crc: "", attributes: "", fileURL: nil, archivePath: nil, isParent: true), at: 0)
        return result
    }

    static func loadDirectory(_ url: URL) -> [PanelItem] {
        var result: [PanelItem] = []
        result.append(PanelItem(name: "..", isDirectory: true, size: 0, packedSize: 0, modified: nil,
                                crc: "", attributes: "", fileURL: nil, archivePath: nil, isParent: true))
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]) else {
            return result
        }
        for f in contents.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let showHidden = UserDefaults.standard.bool(forKey: "BingZipShowHidden")
            if !showHidden && f.lastPathComponent.hasPrefix(".") { continue }
            var isDirFlag: ObjCBool = false
            if !fm.fileExists(atPath: f.path, isDirectory: &isDirFlag) { continue }
            let isDir = isDirFlag.boolValue
            var size: Int64 = 0
            var date: Date? = nil
            if let values = try? f.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) {
                if !isDir { size = Int64(values.fileSize ?? 0) }
                date = values.contentModificationDate
            }
            result.append(PanelItem(name: f.lastPathComponent, isDirectory: isDir, size: size,
                                    packedSize: 0, modified: date, crc: "", attributes: isDir ? "D" : "",
                                    fileURL: f, archivePath: nil, isParent: false))
        }
        return result
    }
}