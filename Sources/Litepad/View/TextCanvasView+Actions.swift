import AppKit

/// クリップボード（コピー/カット/ペースト）・Undo/Redo・ブックマークの各アクション。
extension TextCanvasView {
    @objc func copy(_ sender: Any?) {
        let text: String
        if let rect = normalizedRectSelection {
            text = buffer.rectText(topLine: rect.topLine, bottomLine: rect.bottomLine, leftColumn: rect.leftColumn, rightColumn: rect.rightColumn)
        } else if let selection = normalizedSelection {
            text = buffer.text(from: selection.start, to: selection.end)
        } else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @objc func cut(_ sender: Any?) {
        guard hasSelection else { return }
        copy(sender)
        deleteSelectionIfAny()
        afterEdit()
    }

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        insertReplacingSelection(text)
        unmarkText()
        afterEdit()
    }

    @objc func undo(_ sender: Any?) { undoManager?.undo() }
    @objc func redo(_ sender: Any?) { undoManager?.redo() }

    // MARK: - Bookmarks

    @objc func toggleBookmark(_ sender: Any?) {
        bookmarkStore.toggle(cursor.line)
        needsDisplay = true
    }

    @objc func jumpToNextBookmark(_ sender: Any?) {
        guard let next = bookmarkStore.nextLine(after: cursor.line) else { return }
        jumpToBookmarkLine(next)
    }

    @objc func jumpToPreviousBookmark(_ sender: Any?) {
        guard let prev = bookmarkStore.previousLine(before: cursor.line) else { return }
        jumpToBookmarkLine(prev)
    }

    private func jumpToBookmarkLine(_ line: Int) {
        clearSelection()
        cursor = CursorPosition(line: line, column: 0)
        afterCursorMove()
    }
}
