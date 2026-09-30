import XCTest
@testable import Litepad

final class GrepEngineTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testParsePatternsSplitsOnSemicolonAndTrims() {
        XCTAssertEqual(GrepEngine.parsePatterns("*.txt; *.java ;*.md"), ["*.txt", "*.java", "*.md"])
        XCTAssertEqual(GrepEngine.parsePatterns(""), [])
        XCTAssertEqual(GrepEngine.parsePatterns("*"), ["*"])
    }

    func testEnumerateFilesFiltersByPattern() throws {
        try "a".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: tempDir.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        try "c".write(to: tempDir.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)

        let results = GrepEngine.enumerateFiles(in: tempDir, patterns: ["*.txt"], recursive: false)
        XCTAssertEqual(Set(results.map(\.lastPathComponent)), ["a.txt", "c.txt"])
    }

    func testEnumerateFilesRecursiveVsNonRecursive() throws {
        let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "top".write(to: tempDir.appendingPathComponent("top.txt"), atomically: true, encoding: .utf8)
        try "nested".write(to: sub.appendingPathComponent("nested.txt"), atomically: true, encoding: .utf8)

        let shallow = GrepEngine.enumerateFiles(in: tempDir, patterns: ["*.txt"], recursive: false)
        XCTAssertEqual(shallow.map(\.lastPathComponent), ["top.txt"])

        let deep = GrepEngine.enumerateFiles(in: tempDir, patterns: ["*.txt"], recursive: true)
        XCTAssertEqual(Set(deep.map(\.lastPathComponent)), ["top.txt", "nested.txt"])
    }

    func testSearchFindsMatchesAcrossFiles() throws {
        try "hello world\nTODO: fix this".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "nothing here".write(to: tempDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let matches = try GrepEngine.search(
            folder: tempDir,
            patterns: ["*.txt"],
            recursive: false,
            query: "TODO",
            useRegex: false,
            caseSensitive: true
        )
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].fileURL.lastPathComponent, "a.txt")
        XCTAssertEqual(matches[0].lineNumber, 2)
    }

    func testSearchWithNoPatternMatchesAllFiles() throws {
        try "keyword".write(to: tempDir.appendingPathComponent("a.log"), atomically: true, encoding: .utf8)
        let matches = try GrepEngine.search(
            folder: tempDir,
            patterns: [],
            recursive: false,
            query: "keyword",
            useRegex: false,
            caseSensitive: true
        )
        XCTAssertEqual(matches.count, 1)
    }

    func testSearchRegexCaretAndDollarMatchLineBoundaries() throws {
        try "foo\nbar".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let caretMatches = try GrepEngine.search(
            folder: tempDir, patterns: ["*.txt"], recursive: false, query: "^", useRegex: true, caseSensitive: true
        )
        XCTAssertEqual(caretMatches.count, 2)
        XCTAssertEqual(caretMatches.map(\.startColumn), [0, 0])

        let dollarMatches = try GrepEngine.search(
            folder: tempDir, patterns: ["*.txt"], recursive: false, query: "$", useRegex: true, caseSensitive: true
        )
        XCTAssertEqual(dollarMatches.map(\.startColumn), [3, 3])
    }
}
