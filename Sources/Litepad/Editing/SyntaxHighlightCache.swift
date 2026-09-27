import Foundation

/// 各行の「行頭時点での継続状態」（ブロックコメント中／複数行文字列中）の遅延キャッシュ。
/// index 0は常に`.normal`。巨大ファイルで編集の度に全行を再走査しないよう、
/// 可視行を描画する際に必要な分だけ延長する。
final class SyntaxHighlightCache {
    private var stateAtLineStart: [LineLexState] = [.normal]

    /// `lineIdx`以降の状態を無効化する（`lineIdx`より前の行の内容は変わっていない前提）。
    func invalidate(from lineIdx: Int) {
        let keepCount = max(1, lineIdx + 1)
        if keepCount < stateAtLineStart.count {
            stateAtLineStart.removeSubrange(keepCount...)
        }
    }

    /// `lineIdx`行頭での継続状態。未計算ならその手前まで遅延して埋める。
    func state(atStartOf lineIdx: Int, buffer: DocumentBuffer, language: LanguageDefinition) -> LineLexState {
        while stateAtLineStart.count <= lineIdx {
            let i = stateAtLineStart.count - 1
            let (_, endState) = SyntaxHighlighter.tokenize(
                line: buffer.line(at: i),
                startState: stateAtLineStart[i],
                language: language
            )
            stateAtLineStart.append(endState)
        }
        return stateAtLineStart[lineIdx]
    }
}
