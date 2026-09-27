import Foundation

/// 1件の検索マッチ（行内のみ、複数行にまたがるマッチは対象外）。
struct SearchMatch: Equatable {
    let line: Int
    let startColumn: Int
    let endColumn: Int
}

enum TextSearcher {
    /// ドキュメント全体から一致箇所をすべて探す（行単位、通常検索／正規表現の両対応）。
    static func allMatches(
        in buffer: DocumentBuffer,
        query: String,
        useRegex: Bool,
        caseSensitive: Bool
    ) throws -> [SearchMatch] {
        guard !query.isEmpty else { return [] }

        var regex: NSRegularExpression?
        if useRegex {
            var options: NSRegularExpression.Options = []
            if !caseSensitive { options.insert(.caseInsensitive) }
            regex = try NSRegularExpression(pattern: query, options: options)
        }

        var matches: [SearchMatch] = []
        for lineIdx in 0..<buffer.lineCount {
            let text = buffer.line(at: lineIdx)
            guard !text.isEmpty else { continue }

            if let regex {
                let ns = text as NSString
                for result in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    guard result.range.length > 0, let range = Range(result.range, in: text) else { continue }
                    matches.append(SearchMatch(
                        line: lineIdx,
                        startColumn: text.distance(from: text.startIndex, to: range.lowerBound),
                        endColumn: text.distance(from: text.startIndex, to: range.upperBound)
                    ))
                }
            } else {
                let haystack = caseSensitive ? text : text.lowercased()
                let needle = caseSensitive ? query : query.lowercased()
                var searchStart = haystack.startIndex
                while let found = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
                    matches.append(SearchMatch(
                        line: lineIdx,
                        startColumn: haystack.distance(from: haystack.startIndex, to: found.lowerBound),
                        endColumn: haystack.distance(from: haystack.startIndex, to: found.upperBound)
                    ))
                    searchStart = found.upperBound
                }
            }
        }
        return matches
    }
}
