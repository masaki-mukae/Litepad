import AppKit
import CoreText

/// マウス・キーボードのエントリポイントと、それらが使うカーソル移動計算。
extension TextCanvasView {
    private func position(for point: NSPoint) -> CursorPosition {
        let lineIdx = max(0, min(buffer.lineCount - 1, Int((point.y - topInset) / lineHeight)))
        let ctLine = CTLineCreateWithAttributedString(attributedString(forLine: lineIdx))
        // ガター（行番号領域）をクリックした場合は、その行の先頭にカーソルを置く。
        let localX = max(0, point.x - textStartX)
        let col = CTLineGetStringIndexForPosition(ctLine, CGPoint(x: localX, y: 0))
        return CursorPosition(line: lineIdx, column: max(0, min(buffer.line(at: lineIdx).count, col)))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let newPos = position(for: convert(event.locationInWindow, from: nil))
        let optionHeld = event.modifierFlags.contains(.option)
        if event.modifierFlags.contains(.shift) {
            if selectionAnchor == nil { selectionAnchor = cursor }
            isRectangularSelection = optionHeld
        } else {
            selectionAnchor = newPos
            isRectangularSelection = optionHeld
        }
        cursor = newPos
        unmarkText()
        afterCursorMove()
    }

    override func mouseDragged(with event: NSEvent) {
        cursor = position(for: convert(event.locationInWindow, from: nil))
        autoscroll(with: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if selectionAnchor == cursor { clearSelection(); needsDisplay = true }
    }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(NSResponder.moveLeft(_:)):
            clearSelection(); cursor = leftPosition(); afterCursorMove()
        case #selector(NSResponder.moveRight(_:)):
            clearSelection(); cursor = rightPosition(); afterCursorMove()
        case #selector(NSResponder.moveUp(_:)):
            clearSelection(); cursor = upPosition(); afterCursorMove()
        case #selector(NSResponder.moveDown(_:)):
            clearSelection(); cursor = downPosition(); afterCursorMove()
        case #selector(NSResponder.moveToBeginningOfLine(_:)):
            clearSelection(); cursor.column = 0; afterCursorMove()
        case #selector(NSResponder.moveToEndOfLine(_:)):
            clearSelection(); cursor.column = buffer.line(at: cursor.line).count; afterCursorMove()
        case #selector(NSResponder.moveLeftAndModifySelection(_:)):
            extendSelection(to: leftPosition()); afterCursorMove()
        case #selector(NSResponder.moveRightAndModifySelection(_:)):
            extendSelection(to: rightPosition()); afterCursorMove()
        case #selector(NSResponder.moveUpAndModifySelection(_:)):
            extendSelection(to: upPosition()); afterCursorMove()
        case #selector(NSResponder.moveDownAndModifySelection(_:)):
            extendSelection(to: downPosition()); afterCursorMove()
        case #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:)):
            var p = cursor; p.column = 0; extendSelection(to: p); afterCursorMove()
        case #selector(NSResponder.moveToEndOfLineAndModifySelection(_:)):
            var p = cursor; p.column = buffer.line(at: cursor.line).count; extendSelection(to: p); afterCursorMove()
        case #selector(NSResponder.deleteBackward(_:)):
            if hasSelection {
                deleteSelectionIfAny()
            } else {
                let start = leftPosition()
                if start != cursor { applyEdit(from: start, to: cursor, withText: "") }
            }
            afterEdit()
        case #selector(NSResponder.insertNewline(_:)):
            insertNewlineWithAutoIndent()
            afterEdit()
        case #selector(NSResponder.insertTab(_:)):
            insertReplacingSelection("\t")
            afterEdit()
        default:
            super.doCommand(by: selector)
        }
    }

    override func selectAll(_ sender: Any?) {
        guard buffer.lineCount > 0 else { return }
        isRectangularSelection = false
        selectionAnchor = CursorPosition(line: 0, column: 0)
        cursor = CursorPosition(line: buffer.lineCount - 1, column: buffer.line(at: buffer.lineCount - 1).count)
        afterCursorMove()
    }

    private func leftPosition() -> CursorPosition {
        if cursor.column > 0 { return CursorPosition(line: cursor.line, column: cursor.column - 1) }
        guard cursor.line > 0 else { return cursor }
        return CursorPosition(line: cursor.line - 1, column: buffer.line(at: cursor.line - 1).count)
    }

    private func rightPosition() -> CursorPosition {
        let len = buffer.line(at: cursor.line).count
        if cursor.column < len { return CursorPosition(line: cursor.line, column: cursor.column + 1) }
        guard cursor.line < buffer.lineCount - 1 else { return cursor }
        return CursorPosition(line: cursor.line + 1, column: 0)
    }

    private func upPosition() -> CursorPosition {
        guard cursor.line > 0 else { return cursor }
        return CursorPosition(line: cursor.line - 1, column: min(cursor.column, buffer.line(at: cursor.line - 1).count))
    }

    private func downPosition() -> CursorPosition {
        guard cursor.line < buffer.lineCount - 1 else { return cursor }
        return CursorPosition(line: cursor.line + 1, column: min(cursor.column, buffer.line(at: cursor.line + 1).count))
    }
}
