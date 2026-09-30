import AppKit

/// 検索・置換（`FindPanelController`・`GrepWindowController`から呼ばれる）。
extension TextCanvasView {
    typealias FindOutcome = (found: Bool, total: Int, index: Int?)

    /// Grep結果のダブルクリックなど、既知の位置に直接ジャンプして選択状態にする。
    func revealMatch(line: Int, startColumn: Int, endColumn: Int) {
        guard line >= 0, line < buffer.lineCount else { return }
        isRectangularSelection = false
        selectionAnchor = CursorPosition(line: line, column: startColumn)
        cursor = CursorPosition(line: line, column: endColumn)
        afterCursorMove()
        window?.makeFirstResponder(self)
    }

    @discardableResult
    func performFind(query: String, useRegex: Bool, caseSensitive: Bool, forward: Bool) throws -> FindOutcome {
        let matches = try TextSearcher.allMatches(in: buffer, query: query, useRegex: useRegex, caseSensitive: caseSensitive)
        guard !matches.isEmpty else { return (false, 0, nil) }

        let anchorPosition: CursorPosition
        if let selection = normalizedSelection {
            anchorPosition = forward ? selection.end : selection.start
        } else {
            anchorPosition = cursor
        }

        // 幅ゼロのマッチ(`^`単体など)を選択中に「次を検索」すると、選択終了位置が
        // マッチ開始位置と同じになるため、`>=`のままだと同じマッチを永久に選び直してしまう。
        // 現在の選択がちょうどいずれかのマッチと一致する場合は、そのマッチを候補から除外する。
        let currentMatch = normalizedSelection.flatMap { selection in
            matches.first {
                $0.line == selection.start.line
                    && $0.startColumn == selection.start.column
                    && $0.endColumn == selection.end.column
            }
        }
        let forwardCandidates = currentMatch.map { current in matches.filter { $0 != current } } ?? matches
        let searchPool = forwardCandidates.isEmpty ? matches : forwardCandidates

        let match: SearchMatch
        if forward {
            match = searchPool.first(where: { CursorPosition(line: $0.line, column: $0.startColumn) >= anchorPosition }) ?? searchPool[0]
        } else {
            match = matches.last(where: { CursorPosition(line: $0.line, column: $0.startColumn) < anchorPosition }) ?? matches[matches.count - 1]
        }

        isRectangularSelection = false
        selectionAnchor = CursorPosition(line: match.line, column: match.startColumn)
        cursor = CursorPosition(line: match.line, column: match.endColumn)
        afterCursorMove()

        let index = matches.firstIndex(of: match).map { $0 + 1 }
        return (true, matches.count, index)
    }

    @discardableResult
    func performReplaceCurrentAndFindNext(
        query: String,
        useRegex: Bool,
        caseSensitive: Bool,
        replacement: String
    ) throws -> FindOutcome {
        if let selection = normalizedSelection, selection.start.line == selection.end.line {
            applyEdit(from: selection.start, to: selection.end, withText: replacement)
            afterEdit()
        }
        return try performFind(query: query, useRegex: useRegex, caseSensitive: caseSensitive, forward: true)
    }

    @discardableResult
    func performReplaceAll(query: String, useRegex: Bool, caseSensitive: Bool, replacement: String) throws -> Int {
        let matches = try TextSearcher.allMatches(in: buffer, query: query, useRegex: useRegex, caseSensitive: caseSensitive)
        guard !matches.isEmpty else { return 0 }

        undoManager?.beginUndoGrouping()
        // 後ろから置換することで、未処理のマッチの行内オフセットがずれないようにする。
        for match in matches.reversed() {
            applyEdit(
                from: CursorPosition(line: match.line, column: match.startColumn),
                to: CursorPosition(line: match.line, column: match.endColumn),
                withText: replacement
            )
        }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("すべて置換")

        clearSelection()
        afterEdit()
        return matches.count
    }
}
