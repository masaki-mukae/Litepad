import Foundation

/// ウィンドウ下部に表示する「選択中の文字数/バイト数」のテキストを組み立てる
/// （サクラエディタの`CViewSelect::PrintSelectionInfoMsg`相当だが、文字数とバイト数を
/// 切り替えではなく同時に表示する点はLitepad独自の拡張）。矩形選択の場合は桁数×行数、
/// 通常選択の場合は文字数/バイト数と行数を表示する。選択が無い場合は空文字列を返す。
enum SelectionStatusFormatter {
    /// この行数を超える選択は行数だけを表示し、文字数/バイト数の計算は省略する
    /// （数千万行規模のファイルで「すべて選択」しても固まらないための最終防衛ライン）。
    /// `countSelected`が未実体化行をデコードせずに済むよう最適化されているため
    /// （`DocumentBuffer.peekLine`/`lineByteLength`参照）、以前よりずっと大きい値でも
    /// 実用的な速度で計算できる。
    static let maxLinesForExactCount = 2_000_000

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
    /// 境界となる先頭行・末尾行だけは列位置での切り出しが必要なため`peekLine`でデコードするが、
    /// 内部の行は文字数を数える以外の目的が無いため、バイト数は`lineByteLength`（未編集行なら
    /// デコード不要）、文字数は`peekLine(...).count`（`Array`化や再構築をしない）で済ませる。
    /// `peekLine`は`line(at:)`と違って実体化キャッシュに残さないため、巨大範囲を読んでも
    /// ファイル全体が恒久的にメモリへ展開されることはない。
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
            let chars = Array(buffer.peekLine(at: start.line))
            let from = min(max(start.column, 0), chars.count)
            let to = min(max(end.column, 0), chars.count)
            guard from < to else { return (0, 0) }
            return counts(String(chars[from..<to]))
        }

        let startChars = Array(buffer.peekLine(at: start.line))
        let startFrom = min(max(start.column, 0), startChars.count)
        let (startC, startB) = counts(String(startChars[startFrom...]))
        var totalChars = startC + 1
        var totalBytes = startB + newlineBytes

        if end.line > start.line + 1 {
            for lineIdx in (start.line + 1)..<end.line {
                totalChars += buffer.peekLine(at: lineIdx).count + 1
                totalBytes += buffer.lineByteLength(at: lineIdx) + newlineBytes
            }
        }

        let endChars = Array(buffer.peekLine(at: end.line))
        let endTo = min(max(end.column, 0), endChars.count)
        let (endC, endB) = counts(String(endChars[0..<endTo]))
        totalChars += endC
        totalBytes += endB

        return (totalChars, totalBytes)
    }
}
