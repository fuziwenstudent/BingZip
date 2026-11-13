import AppKit

/// Runs 7zz operations with a real progress window.
/// - Cancel really terminates the 7zz process.
/// - Background hides the window while the task keeps running; it can be
///   restored from Tools > Background Tasks.
final class OperationRunner: NSObject {

    static let shared = OperationRunner()
    private(set) var running: [ProgressWindowController] = []

    func start(args: [String],
               title: String,
               window: NSWindow?,
               executable: URL? = nil,
               workingDirectory: URL? = nil,
               completion: @escaping (_ ok: Bool, _ message: String) -> Void) {
        let controller = ProgressWindowController(title: title)
        controller.completion = completion
        running.append(controller)
        controller.showWindow(nil)
        controller.window?.center()
        AppLogger.shared.log("START \(title): \(AppLogger.shared.redactedArguments(args))")

        // Cancel terminates the child process for real
        controller.onCancel = { [weak controller] in
            guard let c = controller else { return }
            c.cancelled = true
            c.setStatus("正在取消…")
            c.process?.terminate()
        }
        // Background just hides the window
        controller.onBackground = { [weak controller] in
            controller?.window?.orderOut(nil)
        }

        let startTime = Date()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var lastLine = ""
            let result = try? SevenZip.shared.run(args,
                                                  executable: executable,
                                                  workingDirectory: workingDirectory,
                                                  streamStdout: true,
                                                  onProcess: { p in
                DispatchQueue.main.async { controller.process = p }
            }, onLine: { line in
                if !line.isEmpty { lastLine = line }
                DispatchQueue.main.async {
                    controller.updateProgress(line: line,
                                              elapsed: Date().timeIntervalSince(startTime))
                }
            })
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.running.removeAll { $0 === controller }
                let ok = (result?.exitCode ?? 1) == 0
                let stderr = result?.stderr ?? ""
                let stdout = result?.stdout ?? ""
                var message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if message.isEmpty { message = stdout.trimmingCharacters(in: .whitespacesAndNewlines) }
                if message.isEmpty { message = lastLine }
                let wasHidden = controller.window?.isVisible == false
                let elapsed = Date().timeIntervalSince(startTime)
                AppLogger.shared.log("END \(title) ok=\(ok) elapsed=\(String(format: "%.1f", elapsed))s message=\(message.prefix(300))")
                controller.finish(success: ok, message: message)
                if wasHidden {
                    // Show the outcome briefly even for background tasks
                    controller.showWindow(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        if controller.window?.isVisible == true {
                            controller.window?.orderOut(nil)
                        }
                    }
                }
            }
        }
    }

    /// Restore hidden background progress windows
    func restoreRunningWindows() {
        for c in running {
            c.showWindow(nil)
            c.window?.makeKeyAndOrderFront(nil)
        }
    }

    var hasRunning: Bool { !running.isEmpty }
}