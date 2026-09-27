import Foundation

/// ブックマークされた行番号の集合を管理する（サクラエディタのブックマーク機能相当）。
final class BookmarkStore {
    private(set) var lines: Set<Int> = []

    func contains(_ line: Int) -> Bool { lines.contains(line) }

    func toggle(_ line: Int) {
        if lines.contains(line) {
            lines.remove(line)
        } else {
            lines.insert(line)
        }
    }

    func nextLine(after line: Int) -> Int? {
        guard !lines.isEmpty else { return nil }
        let sorted = lines.sorted()
        return sorted.first(where: { $0 > line }) ?? sorted.first
    }

    func previousLine(before line: Int) -> Int? {
        guard !lines.isEmpty else { return nil }
        let sorted = lines.sorted()
        return sorted.last(where: { $0 < line }) ?? sorted.last
    }

    /// 編集で行数が変化した場合に、ブックマーク済みの行番号を追従させる。編集範囲より前の
    /// ブックマークはそのまま、編集範囲より後ろのブックマークは行数の増減ぶんだけずらす。
    /// 編集範囲の内側（潰された行）にあったブックマークは対象の行ごと無くなったとみなして外す。
    func adjust(editStart start: CursorPosition, oldEnd end: CursorPosition, newEnd: CursorPosition) {
        guard !lines.isEmpty else { return }
        let lineDelta = newEnd.line - end.line
        guard lineDelta != 0 else { return }
        var updated: Set<Int> = []
        for line in lines {
            if line <= start.line {
                updated.insert(line)
            } else if line > end.line {
                updated.insert(line + lineDelta)
            }
        }
        lines = updated
    }
}
