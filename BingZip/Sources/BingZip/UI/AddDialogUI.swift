import Foundation
import AppKit

extension AddDialog {

    /// 面向普通用户的精简压缩界面:只保留保存位置、格式、压缩程度、密码。
    /// 其余专业参数仍会以默认值参与压缩,但不打扰用户。
    func setup(suggest: URL) {
        guard let cv = window?.contentView else { return }

        archiveField = NSTextField()
        let baseName = sources.first.map { $0.deletingPathExtension().lastPathComponent } ?? "archive"
        archiveField.stringValue = suggest.appendingPathComponent(baseName + ".7z").path
        archiveField.font = .systemFont(ofSize: 12)

        // 隐藏控件:保留默认值,供参数拼装使用
        updatePopup = comboBox(["添加并替换文件", "添加并更新文件"])
        formatPopup = comboBox(["7z", "Zip", "RAR", "Tar", "GZip", "XZ", "BZip2", "WIM"])
        levelPopup = comboBox(ArgsBuilder.levels.map { $0.0 }, select: 3)
        methodPopup = comboBox(ArgsBuilder.methods(for: "7z"))
        dictPopup = comboBox(ArgsBuilder.dictSizes(for: "LZMA2"), select: 9)
        wordField = NSTextField()
        wordField.stringValue = "64"
        threadsPopup = comboBox(["(默认)", "1", "2", "4", "6", "8", "16"])
        solidPopup = comboBox(["(默认)", "开启", "关闭"])
        memLabel = NSTextField(labelWithString: "")
        volumeField = NSTextField()
        volumeUnitPopup = comboBox(["字节", "KB", "MB", "GB"], select: 2)
        pathModePopup = comboBox(["相对路径名称", "完整路径名称", "绝对路径名称", "无路径"])
        paramsField = NSTextField()
        excludeField = NSTextField()
        encryptHeaderButton = NSButton(checkboxWithTitle: "加密文件名", target: nil, action: nil)
        symlinkButton = NSButton(checkboxWithTitle: "存储符号链接", target: nil, action: nil)

        passwordField = NSSecureTextField()
        passwordField.placeholderString = "不设置请留空"
        password2Field = NSSecureTextField()
        password2Field.placeholderString = "再输入一次密码"

        deleteSourceButton = NSButton(checkboxWithTitle: "压缩完成后删除原文件", target: nil, action: nil)

        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        methodPopup.target = self
        methodPopup.action = #selector(settingsChanged)
        dictPopup.target = self
        dictPopup.action = #selector(settingsChanged)
        levelPopup.target = self
        levelPopup.action = #selector(settingsChanged)

        // 标题
        let header = label("把 \(sources.count) 个项目压缩成一个文件")
        header.font = .systemFont(ofSize: 13, weight: .semibold)

        let grid = NSGridView(views: [])
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.addRow(with: [label("保存为:"), archiveField,
                           NSButton(title: "浏览…", target: self, action: #selector(browseDest))])
        grid.addRow(with: [label("文件格式:"), formatPopup])
        grid.addRow(with: [label("压缩程度:"), levelPopup])
        grid.addRow(with: [label("密码(可选):"), passwordField])
        grid.addRow(with: [label("确认密码:"), password2Field])
        grid.addRow(with: [deleteSourceButton])
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        let hint = label("提示:压缩程度越高,文件越小,但需要的时间更长。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hintLabel = hint

        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelClick))
        cancel.keyEquivalent = "\u{1b}"
        cancel.bezelStyle = .rounded
        let ok = NSButton(title: "开始压缩", target: self, action: #selector(okClick))
        ok.keyEquivalent = "\r"
        ok.bezelStyle = .rounded

        let buttons = NSStackView(views: [cancel, ok])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false

        cv.addSubview(header)
        cv.addSubview(grid)
        cv.addSubview(hint)
        cv.addSubview(buttons)
        header.translatesAutoresizingMaskIntoConstraints = false
        hint.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: cv.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 18),

            grid.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            grid.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 18),
            grid.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -18),
            archiveField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),

            hint.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 12),
            hint.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 18),

            buttons.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -16),
            buttons.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -18),
        ])

        updateMemoryLabel()
        updateResponsiveLayout()
    }
}
