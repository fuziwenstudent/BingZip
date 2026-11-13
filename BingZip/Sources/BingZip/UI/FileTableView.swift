import AppKit

/// NSTableView subclass adding 7-Zip / Finder style keyboard navigation.
/// The main menu also carries most shortcuts; this handles the keys that are
/// most natural while the file list itself has focus.
final class FileTableView: NSTableView {

    weak var panel: FilePanel?

    override func keyDown(with event: NSEvent) {
        guard let panel = panel else {
            super.keyDown(with: event)
            return
        }

        // Ignore caps lock / fn / numpad noise; only real modifiers matter.
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

        // Return / keypad Enter → open the selected item.
        if event.keyCode == 36 || event.keyCode == 76 {
            panel.openSelected()
            return
        }

        // F2 → rename (7-Zip convention).
        if event.keyCode == 120 && modifiers.isEmpty {
            panel.doRename()
            return
        }

        // ⌘⌫ → move to Trash; plain ⌫ → parent folder (7-Zip convention).
        if event.keyCode == 51 || event.keyCode == 117 {
            if modifiers == .command {
                panel.doDelete()
            } else if modifiers.isEmpty {
                panel.navigateUp()
            } else {
                super.keyDown(with: event)
            }
            return
        }

        if modifiers == .command {
            switch event.keyCode {
            case 126: // ↑
                panel.navigateUp()
                return
            case 125: // ↓
                panel.openSelected()
                return
            case 123: // ←
                panel.goBack()
                return
            case 124: // →
                panel.goForward()
                return
            default:
                break
            }

            // 这些快捷键只在文件列表获得焦点时生效,
            // 不会抢走文本框里的 ⌘C / ⌘V / ⌘E / ⌘↑ 等编辑按键。
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                switch chars {
                case "[": panel.goBack(); return
                case "]": panel.goForward(); return
                case "e": panel.doExtract(); return
                case "t": panel.doTest(); return
                default: break
                }
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - Standard edit actions (responder chain)

    @objc func copy(_ sender: Any?) { panel?.doCopy() }
    @objc func paste(_ sender: Any?) { panel?.doPaste() }
    // 全选交给 NSTableView 原生实现(与 FilePanel.doSelectAll 等价,
    // 且避免 doSelectAll → tableView.selectAll → override 的递归)。
}
