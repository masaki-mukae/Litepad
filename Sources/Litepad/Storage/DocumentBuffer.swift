import Foundation

struct CursorPosition: Equatable, Comparable {
    var line: Int
    var column: Int

    static func < (lhs: CursorPosition, rhs: CursorPosition) -> Bool {
        (lhs.line, lhs.column) < (rhs.line, rhs.column)
    }
}

/// テキストを保持するドキュメントモデル。文字コード・改行コードの判定/保持、
/// 挿入・削除・範囲置換・矩形編集・検索置換向けの範囲取得を提供する。
/// 内部の行ストレージは`LineStore`（mmap + 行の遅延実体化）で、巨大ファイルでも
/// 編集された行だけがメモリ上のStringになる。
final class DocumentBuffer {
    private let store: LineStore
    private(set) var fileURL: URL?
    private(set) var lineEnding: LineEnding

    var encoding: TextEncodingKind { store.encoding }

    init(text: String, fileURL: URL? = nil, encoding: TextEncodingKind = .utf8, lineEnding: LineEnding = .lf) {
        store = LineStore(text: text, encoding: encoding)
        self.fileURL = fileURL
        self.lineEnding = lineEnding
    }

    init(contentsOf url: URL) throws {
        let store = try LineStore(contentsOf: url)
        self.store = store
        fileURL = url
        lineEnding = store.detectedLineEnding
    }

    /// クラッシュ復元時など、内容はそのままに保存先の判定（拡張子に基づく構文ハイライト
    /// 言語判定など）だけを付け替えたい場合に使う。
    func reassignFileURL(_ url: URL?) {
        fileURL = url
    }

    /// 文字コードを変換する（内容は変わらず、次回保存時のバイト列表現だけが変わる）。
    func reassignEncoding(_ newEncoding: TextEncodingKind) {
        store.reassignEncoding(newEncoding)
    }

    /// 保存用: 一時ファイルへ書き出してから、最後にアトミックに差し替える。実際の書き出し
    /// ロジック（未編集の連続区間をまとめてコピーする最適化を含む）は`LineStore`に委ねる。
    /// ユーザーが明示的に指定した保存先を`fileURL`として記録する。
    func write(to url: URL) throws {
        try writeSnapshot(to: url)
        fileURL = url
    }

    /// 自動保存のバックアップなど、`fileURL`（＝ドキュメント本来の保存先）は変えたくない
    /// 書き出しに使う。拡張子に基づくシンタックスハイライト判定などが`fileURL`を参照しているため、
    /// バックアップ書き出しのたびにそれを書き換えてしまうと言語判定が壊れてしまう。
    func writeSnapshot(to url: URL) throws {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).litepad-tmp-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: tempURL.path) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try store.write(to: handle, lineEnding: lineEnding)
        try handle.close()

        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: url)
        }
    }

    var lineCount: Int { store.count }

    func line(at index: Int) -> String {
        store.line(at: index)
    }

    @discardableResult
    func insert(_ character: Character, at position: CursorPosition) -> CursorPosition {
        var chars = Array(store.line(at: position.line))
        let col = min(max(position.column, 0), chars.count)
        chars.insert(character, at: col)
        store.setLine(position.line, to: String(chars))
        return CursorPosition(line: position.line, column: col + 1)
    }

    @discardableResult
    func insertNewline(at position: CursorPosition) -> CursorPosition {
        let chars = Array(store.line(at: position.line))
        let col = min(max(position.column, 0), chars.count)
        let head = String(chars[0..<col])
        let tail = String(chars[col...])
        store.setLine(position.line, to: head)
        store.insertLine(tail, at: position.line + 1)
        return CursorPosition(line: position.line + 1, column: 0)
    }

    @discardableResult
    func deleteBackward(at position: CursorPosition) -> CursorPosition {
        if position.column > 0 {
            var chars = Array(store.line(at: position.line))
            chars.remove(at: position.column - 1)
            store.setLine(position.line, to: String(chars))
            return CursorPosition(line: position.line, column: position.column - 1)
        } else if position.line > 0 {
            let prev = store.line(at: position.line - 1)
            let current = store.line(at: position.line)
            let newColumn = prev.count
            store.setLine(position.line - 1, to: prev + current)
            store.removeLine(at: position.line)
            return CursorPosition(line: position.line - 1, column: newColumn)
        }
        return position
    }

    /// `start`は`end`より前（または同じ）である前提。範囲内のテキストを取得する。
    func text(from start: CursorPosition, to end: CursorPosition) -> String {
        guard start < end else { return "" }
        if start.line == end.line {
            let chars = Array(store.line(at: start.line))
            let from = min(max(start.column, 0), chars.count)
            let to = min(max(end.column, 0), chars.count)
            guard from < to else { return "" }
            return String(chars[from..<to])
        }
        var parts: [String] = []
        let startChars = Array(store.line(at: start.line))
        let from = min(max(start.column, 0), startChars.count)
        parts.append(String(startChars[from...]))
        if end.line > start.line + 1 {
            for lineIdx in (start.line + 1)..<end.line {
                parts.append(store.line(at: lineIdx))
            }
        }
        let endChars = Array(store.line(at: end.line))
        let to = min(max(end.column, 0), endChars.count)
        parts.append(String(endChars[0..<to]))
        return parts.joined(separator: "\n")
    }

    /// `start`は`end`より前（または同じ）である前提。範囲内のテキストを削除し、
    /// 削除後のカーソル位置（=start）を返す。
    @discardableResult
    func deleteRange(from start: CursorPosition, to end: CursorPosition) -> CursorPosition {
        guard start < end else { return start }
        if start.line == end.line {
            var chars = Array(store.line(at: start.line))
            let from = min(max(start.column, 0), chars.count)
            let to = min(max(end.column, 0), chars.count)
            guard from < to else { return start }
            chars.removeSubrange(from..<to)
            store.setLine(start.line, to: String(chars))
            return CursorPosition(line: start.line, column: from)
        }
        let startChars = Array(store.line(at: start.line))
        let from = min(max(start.column, 0), startChars.count)
        let head = String(startChars[0..<from])
        let endChars = Array(store.line(at: end.line))
        let to = min(max(end.column, 0), endChars.count)
        let tail = String(endChars[to...])
        store.setLine(start.line, to: head + tail)
        store.removeLines((start.line + 1)..<(end.line + 1))
        return CursorPosition(line: start.line, column: from)
    }

    /// 矩形選択範囲（`topLine`〜`bottomLine`の各行における`leftColumn`〜`rightColumn`列）のテキストを取得する。
    /// 各行の実際の長さに合わせてクランプする（短い行は空文字列になる）。
    func rectText(topLine: Int, bottomLine: Int, leftColumn: Int, rightColumn: Int) -> String {
        var parts: [String] = []
        for lineIdx in topLine...bottomLine {
            let chars = Array(store.line(at: lineIdx))
            let from = min(max(leftColumn, 0), chars.count)
            let to = min(max(rightColumn, 0), chars.count)
            parts.append(from < to ? String(chars[from..<to]) : "")
        }
        return parts.joined(separator: "\n")
    }

    /// 矩形選択範囲を各行から削除し、カーソル位置（=左上）を返す。
    @discardableResult
    func deleteRect(topLine: Int, bottomLine: Int, leftColumn: Int, rightColumn: Int) -> CursorPosition {
        for lineIdx in topLine...bottomLine {
            var chars = Array(store.line(at: lineIdx))
            let from = min(max(leftColumn, 0), chars.count)
            let to = min(max(rightColumn, 0), chars.count)
            guard from < to else { continue }
            chars.removeSubrange(from..<to)
            store.setLine(lineIdx, to: String(chars))
        }
        return CursorPosition(line: topLine, column: leftColumn)
    }

    /// 各行の同じ列位置に同じ文字列を挿入する（矩形貼り付け／矩形上書き用）。
    /// 対象行が`column`より短い場合は空白で埋めてから挿入し、矩形としての整列を保つ。
    @discardableResult
    func insertRect(_ text: String, topLine: Int, bottomLine: Int, column: Int) -> CursorPosition {
        for lineIdx in topLine...bottomLine {
            var chars = Array(store.line(at: lineIdx))
            if chars.count < column {
                chars.append(contentsOf: repeatElement(Character(" "), count: column - chars.count))
            }
            chars.insert(contentsOf: text, at: column)
            store.setLine(lineIdx, to: String(chars))
        }
        return CursorPosition(line: topLine, column: column + text.count)
    }

    /// `start`〜`end`を`text`（改行を含んでもよい）で置き換える汎用の置換。
    /// 全ての編集操作（挿入・削除・選択の置き換え・検索置換）の基盤となる。
    @discardableResult
    func replace(from start: CursorPosition, to end: CursorPosition, withText text: String) -> CursorPosition {
        var position = deleteRange(from: start, to: end)
        for char in text {
            position = char == "\n" ? insertNewline(at: position) : insert(char, at: position)
        }
        return position
    }

    /// 指定行を丸ごと置き換える（矩形編集のUndo/Redo向け）。
    func replaceLine(_ index: Int, with text: String) {
        guard index >= 0, index < store.count else { return }
        store.setLine(index, to: text)
    }
}
