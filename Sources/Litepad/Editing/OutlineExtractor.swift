import Foundation

/// アウトライン1項目（型または関数/メソッドの宣言）。
struct OutlineItem: Equatable {
    let title: String
    /// 0-indexedの行番号。
    let line: Int
    /// ソース行の先頭空白の数。厳密な構文解析はしないため、あくまで見た目のネスト表現に使う。
    let indent: Int
}

/// ファイル内の型（class/struct/enum等）と関数/メソッドの一覧を抽出する（サクラエディタの
/// アウトライン解析相当）。正確な構文解析ではなく、行頭付近のキーワードの直後に来る識別子を
/// 拾う軽量なヒューリスティックのため、`SyntaxHighlighting.swift`と同じ設計思想を踏襲している。
/// C/C++/Javaのような「関数に専用キーワードが無い」言語は型宣言のみを対象にする
/// （戻り値型＋名前＋引数列からの関数抽出は誤検出が多く、実装コストに見合わないため）。
/// COBOLの段落名（固定列書式）も同様の理由で対象外。
enum OutlineExtractor {
    /// 巨大なログファイル等を誤って開いた際に全行走査してしまわないよう、上限を設ける。
    private static let maxLinesScanned = 200_000

    static func extract(from buffer: DocumentBuffer, fileExtension: String) -> [OutlineItem] {
        let ext = fileExtension.lowercased()
        if texExtensions.contains(ext) {
            return extractTeXSections(from: buffer)
        }
        guard let rules = rules(forExtension: ext) else { return [] }

        var items: [OutlineItem] = []
        let lineCount = min(buffer.lineCount, maxLinesScanned)
        for lineIdx in 0..<lineCount {
            let line = buffer.line(at: lineIdx)
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            guard !trimmed.isEmpty else { continue }
            let indent = line.count - trimmed.count

            for rule in rules {
                if let name = rule.match(String(trimmed)) {
                    items.append(OutlineItem(title: rule.titlePrefix + name, line: lineIdx, indent: indent))
                    break
                }
            }
        }
        return items
    }

    // MARK: - キーワード＋識別子ルール

    private struct Rule {
        let keyword: String
        let caseSensitive: Bool
        let titlePrefix: String

        /// トリム済みの行の中に`keyword`が単語境界つきで現れれば、直後の識別子を返す。
        /// 行頭ちょうどでの一致に限らないのは、`public class Foo`や`Public Sub DoWork`のような
        /// 可視性修飾子つきの宣言も拾うため。前後が空白/タブであることを要求するのは、
        /// "class"が"classify"のような識別子の一部に誤反応しないため。キーワードより前に
        /// 括弧やクォートがあれば（＝コメントや文字列の中身、呼び出し式の一部などの可能性が
        /// 高いため）誤検出とみなして無視する。
        func match(_ trimmedLine: String) -> String? {
            let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
            guard let range = trimmedLine.range(of: keyword, options: options) else { return nil }

            if range.lowerBound != trimmedLine.startIndex {
                let before = trimmedLine.index(before: range.lowerBound)
                guard trimmedLine[before] == " " || trimmedLine[before] == "\t" else { return nil }
            }
            guard range.upperBound < trimmedLine.endIndex else { return nil }
            guard trimmedLine[range.upperBound] == " " || trimmedLine[range.upperBound] == "\t" else { return nil }

            let precedingText = trimmedLine[trimmedLine.startIndex..<range.lowerBound]
            guard !precedingText.contains(where: { "{}();\"'".contains($0) }) else { return nil }

            let rest = trimmedLine[range.upperBound...].drop(while: { $0 == " " || $0 == "\t" })
            let name = rest.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
            guard !name.isEmpty else { return nil }
            return String(name)
        }
    }

    private static func rules(forExtension ext: String) -> [Rule]? {
        switch ext {
        case "swift", "kt":
            return [
                Rule(keyword: "class", caseSensitive: true, titlePrefix: "class "),
                Rule(keyword: "struct", caseSensitive: true, titlePrefix: "struct "),
                Rule(keyword: "enum", caseSensitive: true, titlePrefix: "enum "),
                Rule(keyword: "protocol", caseSensitive: true, titlePrefix: "protocol "),
                Rule(keyword: "extension", caseSensitive: true, titlePrefix: "extension "),
                Rule(keyword: "func", caseSensitive: true, titlePrefix: "func "),
            ]
        case "go":
            return [
                Rule(keyword: "func", caseSensitive: true, titlePrefix: "func "),
                Rule(keyword: "type", caseSensitive: true, titlePrefix: "type "),
            ]
        case "rs":
            return [
                Rule(keyword: "fn", caseSensitive: true, titlePrefix: "fn "),
                Rule(keyword: "struct", caseSensitive: true, titlePrefix: "struct "),
                Rule(keyword: "enum", caseSensitive: true, titlePrefix: "enum "),
                Rule(keyword: "trait", caseSensitive: true, titlePrefix: "trait "),
                Rule(keyword: "impl", caseSensitive: true, titlePrefix: "impl "),
            ]
        case "js", "jsx", "ts", "tsx":
            return [
                Rule(keyword: "class", caseSensitive: true, titlePrefix: "class "),
                Rule(keyword: "function", caseSensitive: true, titlePrefix: "function "),
                Rule(keyword: "interface", caseSensitive: true, titlePrefix: "interface "),
            ]
        case "c", "h", "cpp", "cxx", "cc", "cp", "hpp", "hxx", "hh", "hp":
            return [
                Rule(keyword: "class", caseSensitive: true, titlePrefix: "class "),
                Rule(keyword: "struct", caseSensitive: true, titlePrefix: "struct "),
                Rule(keyword: "namespace", caseSensitive: true, titlePrefix: "namespace "),
                Rule(keyword: "enum", caseSensitive: true, titlePrefix: "enum "),
            ]
        case "java", "jav":
            return [
                Rule(keyword: "class", caseSensitive: true, titlePrefix: "class "),
                Rule(keyword: "interface", caseSensitive: true, titlePrefix: "interface "),
                Rule(keyword: "enum", caseSensitive: true, titlePrefix: "enum "),
            ]
        case "py":
            return [
                Rule(keyword: "class", caseSensitive: true, titlePrefix: "class "),
                Rule(keyword: "def", caseSensitive: true, titlePrefix: "def "),
            ]
        case "pas", "dpr":
            return [
                Rule(keyword: "procedure", caseSensitive: false, titlePrefix: "procedure "),
                Rule(keyword: "function", caseSensitive: false, titlePrefix: "function "),
            ]
        case "bas", "frm", "cls", "ctl", "vb":
            return [
                Rule(keyword: "Sub", caseSensitive: false, titlePrefix: "Sub "),
                Rule(keyword: "Function", caseSensitive: false, titlePrefix: "Function "),
                Rule(keyword: "Class", caseSensitive: false, titlePrefix: "Class "),
                Rule(keyword: "Property", caseSensitive: false, titlePrefix: "Property "),
            ]
        case "pl", "pm", "cgi":
            return [Rule(keyword: "sub", caseSensitive: true, titlePrefix: "sub ")]
        case "sql", "plsql":
            return [
                Rule(keyword: "CREATE PROCEDURE", caseSensitive: false, titlePrefix: "PROCEDURE "),
                Rule(keyword: "CREATE FUNCTION", caseSensitive: false, titlePrefix: "FUNCTION "),
                Rule(keyword: "CREATE TABLE", caseSensitive: false, titlePrefix: "TABLE "),
                Rule(keyword: "CREATE VIEW", caseSensitive: false, titlePrefix: "VIEW "),
            ]
        case "awk":
            return [Rule(keyword: "function", caseSensitive: true, titlePrefix: "function ")]
        default:
            return nil
        }
    }

    // MARK: - TeX（`\section{...}`系はキーワード＋識別子の形と異なるため専用処理）

    private static let texExtensions: Set<String> = ["tex", "ltx", "sty"]
    private static let texMarkers: [(marker: String, level: Int)] = [
        ("\\chapter{", 0), ("\\section{", 1), ("\\subsection{", 2), ("\\subsubsection{", 3),
    ]

    private static func extractTeXSections(from buffer: DocumentBuffer) -> [OutlineItem] {
        var items: [OutlineItem] = []
        let lineCount = min(buffer.lineCount, maxLinesScanned)
        for lineIdx in 0..<lineCount {
            let line = buffer.line(at: lineIdx)
            for (marker, level) in texMarkers {
                guard let markerRange = line.range(of: marker) else { continue }
                let afterMarker = line[markerRange.upperBound...]
                guard let closeBrace = afterMarker.firstIndex(of: "}") else { continue }
                let title = String(afterMarker[afterMarker.startIndex..<closeBrace])
                guard !title.isEmpty else { continue }
                items.append(OutlineItem(title: title, line: lineIdx, indent: level * 4))
                break
            }
        }
        return items
    }
}
