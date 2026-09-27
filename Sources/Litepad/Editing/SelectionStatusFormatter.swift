import Foundation

/// ウィンドウ下部に表示する「選択中の文字数/バイト数」のテキストを組み立てる
/// （サクラエディタの`CViewSelect::PrintSelectionInfoMsg`相当だが、文字数とバイト数を
/// 切り替えではなく同時に表示する点はLitepad独自の拡張）。矩形選択の場合は桁数×行数、
/// 通常選択の場合は文字数/バイト数と行数を表示する。選択が無い場合は空文字列を返す。
enum SelectionStatusFormatter {
    /// この行数を超える選択は、文字数/バイト数を数えるために選択範囲の全行を
    /// メモリに実体化させるコストが無視できなくなるため、行数だけを表示し
    /// 文字数/バイト数の計算は省略する（巨大ファイルの「すべて選択」で固まらないため）。
    static let maxLinesForExactCount = 20_000

    static func text(
        buffer: DocumentBuffer,
        selection: (start: CursorPosition, end: CursorPosition)?,
        rectSelection: (topLine: Int, bottomLine: Int, leftColumn: Int, rightColumn: Int)?
    ) -> String {
        if let rect = rectSelection {
            let columns = rect.rightColumn - rect.leftColumn
            guard columns > 0 else { return "" }
            let lines = rect.bottomLine - rect.topLine + 1
            return "\(columns)桁 × \(lines)行選択中"
        }

        guard let selection, selection.start != selection.end else { return "" }
        let lineCount = selection.end.line - selection.start.line + 1

        guard lineCount <= maxLinesForExactCount else {
            return "\(lineCount)行選択中"
        }

        let counts = countSelected(buffer: buffer, from: selection.start, to: selection.end)
        let base = "\(counts.characters)文字/\(counts.bytes)バイト選択中"
        return lineCount > 1 ? "\(base) (\(lineCount)行)" : base
    }

    /// 選択範囲を1つの巨大な`String`として結合せず、行ごとに文字数とバイト数を合算する
    /// （`DocumentBuffer.text(from:to:)`は選択範囲全体を1つの`String`として結合するため、
    /// 選択範囲がGB級になり得る「すべて選択」のようなケースでメモリを圧迫しかねない）。
    private static func countSelected(
        buffer: DocumentBuffer,
        from start: CursorPosition,
        to end: CursorPosition
    ) -> (characters: Int, bytes: Int) {
        func counts(_ s: String) -> (Int, Int) {
            (s.count, TextFileCodec.encodeLineContent(s, as: buffer.encoding).count)
        }
        let newlineBytes = TextFileCodec.encodeLineContent("\n", as: buffer.encoding).count

        if start.line == end.line {
            let chars = Array(buffer.line(at: start.line))
            let from = min(max(start.column, 0), chars.count)
            let to = min(max(end.column, 0), chars.count)
            guard from < to else { return (0, 0) }
            return counts(String(chars[from..<to]))
        }

        var totalChars = 0
        var totalBytes = 0
        for lineIdx in start.line...end.line {
            let chars = Array(buffer.line(at: lineIdx))
            if lineIdx == start.line {
                let from = min(max(start.column, 0), chars.count)
                let (c, b) = counts(String(chars[from...]))
                totalChars += c + 1
                totalBytes += b + newlineBytes
            } else if lineIdx == end.line {
                let to = min(max(end.column, 0), chars.count)
                let (c, b) = counts(String(chars[0..<to]))
                totalChars += c
                totalBytes += b
            } else {
                let (c, b) = counts(String(chars))
                totalChars += c + 1
                totalBytes += b + newlineBytes
            }
        }
        return (totalChars, totalBytes)
    }
}
