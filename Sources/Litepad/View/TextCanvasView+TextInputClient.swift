import AppKit

/// `NSTextInputClient`準拠（IME入力）と、それに付随する括弧の自動デデント処理。
extension TextCanvasView {
    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        if !hasSelection, text.count == 1, let close = text.first, let open = BracketMatcher.closeToOpen[close],
           isOnlyWhitespaceBeforeCursor() {
            insertClosingBracketWithDedent(close, open: open)
        } else {
            insertReplacingSelection(text)
        }
        unmarkText()
        afterEdit()
    }

    /// カーソルより左が全て空白（＝この行でまだ何も書いていない）かどうか。
    private func isOnlyWhitespaceBeforeCursor() -> Bool {
        let chars = Array(buffer.line(at: cursor.line))
        guard cursor.column <= chars.count else { return false }
        return chars[0..<cursor.column].allSatisfy { $0 == " " || $0 == "\t" }
    }

    /// 字下げだけの行に閉じ括弧を入力したとき、対応する開き括弧の行と同じ字下げに揃えてから
    /// 括弧を挿入する（スマートインデントの「自動デデント」相当）。
    private func insertClosingBracketWithDedent(_ close: Character, open: Character) {
        guard let openPosition = BracketMatcher.findOpeningForPendingClose(in: buffer, cursor: cursor, open: open, close: close) else {
            insertReplacingSelection(String(close))
            return
        }
        let targetIndent = leadingWhitespace(ofLine: openPosition.line)
        let lineStart = CursorPosition(line: cursor.line, column: 0)
        let indentEnd = CursorPosition(line: cursor.line, column: cursor.column)
        applyEdit(from: lineStart, to: indentEnd, withText: targetIndent + String(close))
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        composingText = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        composingLine = composingText.isEmpty ? -1 : cursor.line
        needsDisplay = true
    }

    func unmarkText() {
        composingText = ""
        composingLine = -1
    }

    func hasMarkedText() -> Bool { !composingText.isEmpty }

    func markedRange() -> NSRange {
        hasMarkedText()
            ? NSRange(location: cursor.column, length: composingText.utf16.count)
            : NSRange(location: NSNotFound, length: 0)
    }

    func selectedRange() -> NSRange {
        if let selection = normalizedSelection, selection.start.line == selection.end.line {
            return NSRange(location: selection.start.column, length: selection.end.column - selection.start.column)
        }
        return NSRange(location: cursor.column, length: 0)
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.underlineStyle, .backgroundColor]
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let rectInView = caretRect()
        let rectInWindow = convert(rectInView, to: nil)
        return window?.convertToScreen(rectInWindow) ?? rectInWindow
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }
}
