import Foundation

/// 括弧の対応関係を調べるための状態を持たないユーティリティ（サクラエディタの
/// COLORIDX_BRACKET_PAIR相当）。`TextCanvasView`からカーソル位置・バッファを渡して使う。
enum BracketMatcher {
    static let openToClose: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
    static let closeToOpen: [Character: Character] = [")": "(", "]": "[", "}": "{"]

    /// カーソルが括弧に隣接していれば、対応する括弧の位置とのペアを返す。選択中は呼び出し側で表示しない想定。
    static func matchingPositions(in buffer: DocumentBuffer, cursor: CursorPosition) -> (CursorPosition, CursorPosition)? {
        if let ch = character(in: buffer, at: cursor), let close = openToClose[ch],
           let match = find(in: buffer, from: cursor, open: ch, close: close, forward: true) {
            return (cursor, match)
        }
        if cursor.column > 0 {
            let before = CursorPosition(line: cursor.line, column: cursor.column - 1)
            if let ch = character(in: buffer, at: before), let open = closeToOpen[ch],
               let match = find(in: buffer, from: before, open: open, close: ch, forward: false) {
                return (before, match)
            }
        }
        return nil
    }

    private static func character(in buffer: DocumentBuffer, at position: CursorPosition) -> Character? {
        let chars = Array(buffer.line(at: position.line))
        guard position.column >= 0, position.column < chars.count else { return nil }
        return chars[position.column]
    }

    /// `start`にある括弧（open/closeいずれか）から、対応する括弧をネストを数えながら探す。
    /// 巨大ファイルで対応する括弧が無い場合に無限に走査し続けないよう上限を設ける。
    static func find(in buffer: DocumentBuffer, from start: CursorPosition, open: Character, close: Character, forward: Bool) -> CursorPosition? {
        var depth = 0
        var line = start.line
        var col = start.column
        var budget = 50_000

        while line >= 0, line < buffer.lineCount {
            let chars = Array(buffer.line(at: line))
            while forward ? col < chars.count : col >= 0 {
                budget -= 1
                if budget <= 0 { return nil }
                let ch = chars[col]
                if ch == (forward ? open : close) {
                    depth += 1
                } else if ch == (forward ? close : open) {
                    depth -= 1
                    if depth == 0 { return CursorPosition(line: line, column: col) }
                }
                col += forward ? 1 : -1
            }
            line += forward ? 1 : -1
            if line >= 0, line < buffer.lineCount {
                col = forward ? 0 : Array(buffer.line(at: line)).count - 1
            }
        }
        return nil
    }

    /// カーソル位置に`close`を挿入したと仮定して、対応する`open`をネストを数えながら逆方向に探す
    /// （スマートインデントの自動デデント判定用。まだ挿入されていない文字を仮定して探す点が`find`と異なる）。
    static func findOpeningForPendingClose(in buffer: DocumentBuffer, cursor: CursorPosition, open: Character, close: Character) -> CursorPosition? {
        var depth = 1
        var line = cursor.line
        var col = cursor.column - 1
        var budget = 50_000

        while line >= 0 {
            let chars = Array(buffer.line(at: line))
            while col >= 0 {
                budget -= 1
                if budget <= 0 { return nil }
                let ch = col < chars.count ? chars[col] : " "
                if ch == close {
                    depth += 1
                } else if ch == open {
                    depth -= 1
                    if depth == 0 { return CursorPosition(line: line, column: col) }
                }
                col -= 1
            }
            line -= 1
            if line >= 0 { col = Array(buffer.line(at: line)).count - 1 }
        }
        return nil
    }
}
