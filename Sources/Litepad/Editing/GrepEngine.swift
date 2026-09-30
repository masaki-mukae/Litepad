import Foundation
import Darwin

struct GrepMatch {
    let fileURL: URL
    let lineNumber: Int
    let lineText: String
    let startColumn: Int
    let endColumn: Int
}

/// フォルダ内の複数ファイルを横断検索する（サクラエディタのGrep相当）。
enum GrepEngine {
    /// `patterns`はセミコロン区切りのワイルドカードパターン文字列（例: `*.txt;*.java`）。
    static func parsePatterns(_ raw: String) -> [String] {
        raw.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func enumerateFiles(in folder: URL, patterns: [String], recursive: Bool) -> [URL] {
        let fm = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = recursive
            ? [.skipsHiddenFiles]
            : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: options
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard !isDirectory else { continue }
            if matches(fileName: url.lastPathComponent, patterns: patterns) {
                results.append(url)
            }
        }
        return results
    }

    private static func matches(fileName: String, patterns: [String]) -> Bool {
        guard !patterns.isEmpty else { return true }
        return patterns.contains { fnmatch($0, fileName, 0) == 0 }
    }

    /// 1フォルダ配下を検索し、一致した全行を返す。巨大なフォルダでも一覧UIが固まらないよう
    /// 呼び出し側でバックグラウンドスレッドから呼ぶことを想定する。
    static func search(
        folder: URL,
        patterns: [String],
        recursive: Bool,
        query: String,
        useRegex: Bool,
        caseSensitive: Bool
    ) throws -> [GrepMatch] {
        guard !query.isEmpty else { return [] }

        var regex: NSRegularExpression?
        if useRegex {
            var options: NSRegularExpression.Options = []
            if !caseSensitive { options.insert(.caseInsensitive) }
            regex = try NSRegularExpression(pattern: query, options: options)
        }

        var results: [GrepMatch] = []
        for file in enumerateFiles(in: folder, patterns: patterns, recursive: recursive) {
            guard let data = try? Data(contentsOf: file) else { continue }
            let (text, _) = TextFileCodec.decode(data)
            guard !text.isEmpty else { continue }
            let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            let lines = normalized.components(separatedBy: "\n")

            for (index, line) in lines.enumerated() {
                if let regex {
                    let ns = line as NSString
                    for match in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                        guard let range = Range(match.range, in: line) else { continue }
                        results.append(GrepMatch(
                            fileURL: file,
                            lineNumber: index + 1,
                            lineText: line,
                            startColumn: line.distance(from: line.startIndex, to: range.lowerBound),
                            endColumn: line.distance(from: line.startIndex, to: range.upperBound)
                        ))
                    }
                } else {
                    guard !line.isEmpty else { continue }
                    let haystack = caseSensitive ? line : line.lowercased()
                    let needle = caseSensitive ? query : query.lowercased()
                    var searchStart = haystack.startIndex
                    while let found = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
                        results.append(GrepMatch(
                            fileURL: file,
                            lineNumber: index + 1,
                            lineText: line,
                            startColumn: haystack.distance(from: haystack.startIndex, to: found.lowerBound),
                            endColumn: haystack.distance(from: haystack.startIndex, to: found.upperBound)
                        ))
                        searchStart = found.upperBound
                    }
                }
            }
        }
        return results
    }
}
