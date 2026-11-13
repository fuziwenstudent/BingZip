import AppKit

/// Bandizip 风格的绿色进度条(自绘:圆角轨道 + 绿色填充 / 不确定态流动块)
final class GreenBarView: NSView {

    var value: Double = 0 {
        didSet { needsDisplay = true }
    }

    var indeterminate = false {
        didSet { updateAnimation() }
    }

    private var phase: CGFloat = 0
    private var timer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateAnimation() {
        timer?.invalidate()
        timer = nil
        if indeterminate {
            timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.phase += 0.015
                if self.phase > 1 { self.phase = 0 }
                self.needsDisplay = true
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.quaternaryLabelColor.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        NSColor.systemGreen.setFill()
        if indeterminate {
            let w = bounds.width * 0.26
            let x = phase * max(0, bounds.width - w)
            let rect = NSRect(x: x, y: 0, width: w, height: bounds.height)
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        } else {
            let clamped = min(max(value, 0), 100)
            guard clamped > 0 else { return }
            let w = bounds.width * CGFloat(clamped / 100)
            let rect = NSRect(x: 0, y: 0, width: w, height: bounds.height)
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
    }
}

/// Progress window shown while 7zz works (progress bar, speed, time, cancel/background).
final class ProgressWindowController: NSWindowController, NSWindowDelegate {

    var completion: ((Bool, String) -> Void)?
    var process: Process?
    var cancelled = false
    var onCancel: (() -> Void)?
    var onBackground: (() -> Void)?

    private var startDate = Date()
    private var timer: Timer?
    private var titleLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var progressBar: GreenBarView!
    private var fileBar: GreenBarView!
    private var timeLabel: NSTextField!
    private var percentLabel: NSTextField!
    private var filePercentLabel: NSTextField!
    private var fileTimeLabel: NSTextField!
    private var pauseButton: NSButton!
    private var cancelButton: NSButton!
    private var backgroundButton: NSButton!
    private var paused = false
    private var lastPercent: Double = -1

    init(title: String) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 252),
                         styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered, defer: false)
        // Bandizip 的对话框标题即操作名(提取 / 压缩 / 测试 / 扫描)
        w.title = title.contains("解压") || title.contains("提取") ? "提取"
            : (title.contains("压缩") ? "压缩"
               : (title.contains("测试") ? "测试"
                  : (title.contains("扫描") ? "扫描" : "BingZip")))
        super.init(window: w)
        w.delegate = self
        setupUI(title: title)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI(title: String) {
        guard let contentView = window?.contentView else { return }
        titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle

        detailLabel = NSTextField(labelWithString: "准备中…")
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle

        progressBar = GreenBarView()
        fileBar = GreenBarView()
        fileBar.indeterminate = true

        percentLabel = NSTextField(labelWithString: "0%")
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        timeLabel = NSTextField(labelWithString: "00:00:00 / 00:00:00")
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.alignment = .right

        filePercentLabel = NSTextField(labelWithString: "—")
        filePercentLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        fileTimeLabel = NSTextField(labelWithString: "00:00:00 / 00:00:00")
        fileTimeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        fileTimeLabel.textColor = .secondaryLabelColor
        fileTimeLabel.alignment = .right

        func rowLabel(_ s: String) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.font = .systemFont(ofSize: 12)
            return l
        }
        func flexibleSpacer() -> NSView {
            let v = NSView()
            v.setContentHuggingPriority(.defaultLow, for: .horizontal)
            v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return v
        }

        let g1 = NSStackView(views: [rowLabel("总进度"), flexibleSpacer(), percentLabel, timeLabel])
        g1.orientation = .horizontal
        g1.spacing = 10
        g1.alignment = .centerY
        g1.translatesAutoresizingMaskIntoConstraints = false

        let g2 = NSStackView(views: [rowLabel("当前文件"), flexibleSpacer(), filePercentLabel, fileTimeLabel])
        g2.orientation = .horizontal
        g2.spacing = 10
        g2.alignment = .centerY
        g2.translatesAutoresizingMaskIntoConstraints = false

        backgroundButton = iconButton("arrow.up.right.square", tooltip: "后台运行", action: #selector(backgroundClicked))
        let logButton = iconButton("doc.text.magnifyingglass", tooltip: "打开日志", action: #selector(logClicked))
        let closeButton = iconButton("xmark", tooltip: "关闭窗口", action: #selector(closeClicked))

        pauseButton = NSButton(title: "暂停", target: self, action: #selector(pauseClicked))
        pauseButton.bezelStyle = .rounded
        cancelButton = NSButton(title: "停止", target: self, action: #selector(cancelClicked))
        cancelButton.bezelStyle = .rounded
        pauseButton.widthAnchor.constraint(equalToConstant: 88).isActive = true
        cancelButton.widthAnchor.constraint(equalToConstant: 88).isActive = true

        let leftIcons = NSStackView(views: [backgroundButton, logButton, closeButton])
        leftIcons.orientation = .horizontal
        leftIcons.spacing = 6
        let rightButtons = NSStackView(views: [pauseButton, cancelButton])
        rightButtons.orientation = .horizontal
        rightButtons.spacing = 10
        let bottomRow = NSStackView(views: [leftIcons, flexibleSpacer(), rightButtons])
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 8
        bottomRow.alignment = .centerY
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(g1)
        contentView.addSubview(progressBar)
        contentView.addSubview(g2)
        contentView.addSubview(fileBar)
        contentView.addSubview(detailLabel)
        contentView.addSubview(bottomRow)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        fileBar.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -18),

            g1.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            g1.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            g1.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),

            progressBar.topAnchor.constraint(equalTo: g1.bottomAnchor, constant: 5),
            progressBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            progressBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            progressBar.heightAnchor.constraint(equalToConstant: 18),

            g2.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 10),
            g2.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            g2.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),

            fileBar.topAnchor.constraint(equalTo: g2.bottomAnchor, constant: 5),
            fileBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            fileBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            fileBar.heightAnchor.constraint(equalToConstant: 18),

            detailLabel.topAnchor.constraint(equalTo: fileBar.bottomAnchor, constant: 12),
            detailLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            detailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),

            bottomRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            bottomRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bottomRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            bottomRow.topAnchor.constraint(greaterThanOrEqualTo: detailLabel.bottomAnchor, constant: 10),
        ])
        startTimer()
    }

    private func iconButton(_ symbol: String, tooltip: String, action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage(),
                         target: self, action: action)
        b.bezelStyle = .inline
        b.isBordered = false
        b.toolTip = tooltip
        b.imageScaling = .scaleProportionallyDown
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 24).isActive = true
        b.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return b
    }

    func startTimer() {
        startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let e = Date().timeIntervalSince(self.startDate)
            if self.lastPercent <= 0.1 || self.lastPercent >= 100 {
                self.timeLabel.stringValue = "\(Self.clock(e)) / --:--:--"
            }
        }
    }

    /// 供批量任务(如扫描)使用:直接设置总进度与状态文字
    func setOverall(_ percent: Double, status: String) {
        let clamped = min(max(percent, 0), 100)
        if clamped >= progressBar.value { progressBar.value = clamped }
        lastPercent = clamped
        percentLabel.stringValue = "\(Int(clamped))%"
        detailLabel.stringValue = status
        filePercentLabel.stringValue = "进行中"
        let e = Date().timeIntervalSince(startDate)
        let text = "\(Self.clock(e)) / --:--:--"
        timeLabel.stringValue = text
        fileTimeLabel.stringValue = text
    }

    func setStatus(_ text: String) {
        detailLabel.stringValue = text
    }

    // MARK: - Progress

    func updateProgress(line: String, elapsed: TimeInterval) {
        guard let p = SevenZip.parseProgress(line) else {
            // RARLAB's rar prints plain "Adding ..." / "Done" lines.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Adding ") || trimmed.hasPrefix("Updating ")
                || trimmed.hasPrefix("Creating ") || trimmed.hasPrefix("Done") {
                detailLabel.stringValue = trimmed
            }
            return
        }
        if let pct = p.percent {
            let clamped = min(max(pct, 0), 100)
            if clamped >= progressBar.value {
                progressBar.value = clamped
            }
            lastPercent = clamped
            percentLabel.stringValue = "\(Int(clamped))%"
            filePercentLabel.stringValue = clamped >= 100 ? "100%" : "进行中"
            if clamped > 1 {
                let remain = elapsed * (100 - clamped) / clamped
                let text = "\(Self.clock(elapsed)) / \(Self.clock(elapsed + remain))"
                timeLabel.stringValue = text
                fileTimeLabel.stringValue = text
            }
        }
        // 当前文件路径(7zz 的行格式: "  20% 12 - path/to/file")
        let file = Self.fileName(fromProgressExtra: p.extra)
        if !file.isEmpty {
            detailLabel.stringValue = file
        } else if !p.extra.isEmpty {
            detailLabel.stringValue = p.extra
        }
    }

    func finish(success: Bool, message: String) {
        timer?.invalidate()
        pauseButton.isEnabled = false
        cancelButton.isEnabled = false
        backgroundButton.isEnabled = false
        fileBar.indeterminate = false
        if success {
            fileBar.value = 100
            filePercentLabel.stringValue = "100%"
        }

        if cancelled {
            detailLabel.stringValue = "已取消"
            detailLabel.textColor = .secondaryLabelColor
            percentLabel.stringValue = "—"
            NSApp.requestUserAttention(.informationalRequest)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.window?.orderOut(nil)
            }
        } else if success {
            progressBar.value = 100
            percentLabel.stringValue = "100%"
            detailLabel.stringValue = "完成 ✓"
            let total = Self.clock(Date().timeIntervalSince(startDate))
            timeLabel.stringValue = "\(total) / \(total)"
            fileTimeLabel.stringValue = "\(total) / \(total)"
            NSApp.requestUserAttention(.informationalRequest)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.window?.orderOut(nil)
            }
        } else {
            detailLabel.stringValue = message.isEmpty ? "操作失败" : message
            detailLabel.textColor = .systemRed
            NSApp.requestUserAttention(.criticalRequest)
        }
        completion?(success, message)
    }

    // MARK: - Buttons

    @objc func cancelClicked() {
        cancelButton.isEnabled = false
        pauseButton.isEnabled = false
        backgroundButton.isEnabled = false
        onCancel?()
    }

    @objc func pauseClicked() {
        guard let p = process else { return }
        if paused {
            p.resume()
            paused = false
            pauseButton.title = "暂停"
            detailLabel.stringValue = "已继续"
        } else {
            p.suspend()
            paused = true
            pauseButton.title = "继续"
            detailLabel.stringValue = "已暂停"
        }
    }

    @objc func backgroundClicked() {
        onBackground?()
    }

    @objc func logClicked() {
        NSWorkspace.shared.open(AppLogger.shared.logDirectory)
    }

    @objc func closeClicked() {
        onBackground?()
        window?.orderOut(nil)
    }

    // MARK: - Formatting helpers

    static func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return String(format: "%.0f 秒", seconds) }
        if seconds < 3600 {
            let m = Int(seconds / 60)
            let s = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(m) 分 \(s) 秒"
        }
        let h = Int(seconds / 3600)
        let m = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(h) 时 \(m) 分"
    }

    /// 00:00:00 形式的计时(Bandizip 风格)
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// 从 "12 - path/to/file" 中提取文件名
    static func fileName(fromProgressExtra extra: String) -> String {
        if let r = extra.range(of: " - ") {
            return String(extra[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    static func parseSize(from text: String) -> Int64? {
        guard let r = text.range(of: #"([0-9]+(?:\.[0-9]+)?)\s*(B|KB|MB|GB)"#,
                                 options: .regularExpression) else { return nil }
        let token = String(text[r])
        let parts = token.split(separator: " ")
        guard let numPart = parts.first, let num = Double(numPart) else { return nil }
        let unit = parts.count > 1 ? String(parts[1]).uppercased() : "B"
        switch unit {
        case "GB": return Int64(num * 1024 * 1024 * 1024)
        case "MB": return Int64(num * 1024 * 1024)
        case "KB": return Int64(num * 1024)
        default: return Int64(num)
        }
    }
}