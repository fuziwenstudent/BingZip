import Foundation

/// Shared code-page options for Zip file-name encoding.
/// Used by the About window (integrated control) and the Options menu.
enum CodePage {

    struct Option {
        let title: String
        let value: String
    }

    static let options: [Option] = [
        Option(title: "自动 (UTF-8)", value: ""),
        Option(title: "简体中文 (936)", value: "936"),
        Option(title: "繁体中文 (950)", value: "950"),
        Option(title: "日文 (932)", value: "932"),
        Option(title: "韩文 (949)", value: "949"),
        Option(title: "西欧 (1252)", value: "1252"),
    ]

    static let defaultsKey = "BingZipCodePage"

    static var currentValue: String {
        UserDefaults.standard.string(forKey: defaultsKey) ?? ""
    }

    static var currentIndex: Int {
        options.firstIndex { $0.value == currentValue } ?? 0
    }

    static func set(value: String) {
        UserDefaults.standard.set(value, forKey: defaultsKey)
    }
}
