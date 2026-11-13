import Foundation

/// Central application metadata shown in the About / version dialog, crash
/// reports and menus. Keep this in sync with Resources/Info.plist.
enum AppInfo {

    static let name = "BingZip"
    static let version = "1.2"
    static let build = "12"

    static let author = "谷谷"
    static let websiteDisplay = "https://bankok.pages.dev"
    static let websiteURL = URL(string: websiteDisplay)!

    static let engineName = "7-Zip 26.05"
    static let engineDescription = "7-Zip 26.05 压缩引擎 (7zz)"

    static let rarDownloadPage = URL(string: "https://www.rarlab.com/download.htm")!
}
