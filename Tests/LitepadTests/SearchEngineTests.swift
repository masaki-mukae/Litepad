import XCTest
@testable import Litepad

final class SearchEngineTests: XCTestCase {
    func testPlainSearchFindsAllOccurrences() throws {
        let buffer = DocumentBuffer(text: "foo bar\nbar baz\nfoo foo")
        let matches = try TextSearcher.allMatches(in: buffer, query: "foo", useRegex: false, caseSensitive: true)
        XCTAssertEqual(matches.count, 3)
        XCTAssertEqual(matches[0], SearchMatch(line: 0, startColumn: 0, endColumn: 3))
        XCTAssertEqual(matches[1], SearchMatch(line: 2, startColumn: 0, endColumn: 3))
        XCTAssertEqual(matches[2], SearchMatch(line: 2, startColumn: 4, endColumn: 7))
    }

    func testCaseInsensitiveSearch() throws {
        let buffer = DocumentBuffer(text: "Foo FOO foo")
        let matches = try TextSearcher.allMatches(in: buffer, query: "foo", useRegex: false, caseSensitive: false)
        XCTAssertEqual(matches.count, 3)
    }

    func testCaseSensitiveSearchExcludesDifferentCase() throws {
        let buffer = DocumentBuffer(text: "Foo FOO foo")
        let matches = try TextSearcher.allMatches(in: buffer, query: "foo", useRegex: false, caseSensitive: true)
        XCTAssertEqual(matches.count, 1)
    }

    func testRegexSearch() throws {
        let buffer = DocumentBuffer(text: "a1 b22 c333")
        let matches = try TextSearcher.allMatches(in: buffer, query: "[a-z]\\d+", useRegex: true, caseSensitive: true)
        XCTAssertEqual(matches.count, 3)
        XCTAssertEqual(matches[2], SearchMatch(line: 0, startColumn: 7, endColumn: 11))
    }

    func testEmptyQueryReturnsNoMatches() throws {
        let buffer = DocumentBuffer(text: "anything")
        let matches = try TextSearcher.allMatches(in: buffer, query: "", useRegex: false, caseSensitive: true)
        XCTAssertTrue(matches.isEmpty)
    }

    func testInvalidRegexThrows() {
        let buffer = DocumentBuffer(text: "anything")
        XCTAssertThrowsError(
            try TextSearcher.allMatches(in: buffer, query: "(unclosed", useRegex: true, caseSensitive: true)
        )
    }

    func testCaretMatchesStartOfEveryLine() throws {
        let buffer = DocumentBuffer(text: "foo\nbar\nbaz")
        let matches = try TextSearcher.allMatches(in: buffer, query: "^", useRegex: true, caseSensitive: true)
        XCTAssertEqual(matches, [
            SearchMatch(line: 0, startColumn: 0, endColumn: 0),
            SearchMatch(line: 1, startColumn: 0, endColumn: 0),
            SearchMatch(line: 2, startColumn: 0, endColumn: 0),
        ])
    }

    func testDollarMatchesEndOfEveryLine() throws {
        let buffer = DocumentBuffer(text: "foo\nbar\nbaz")
        let matches = try TextSearcher.allMatches(in: buffer, query: "$", useRegex: true, caseSensitive: true)
        XCTAssertEqual(matches, [
            SearchMatch(line: 0, startColumn: 3, endColumn: 3),
            SearchMatch(line: 1, startColumn: 3, endColumn: 3),
            SearchMatch(line: 2, startColumn: 3, endColumn: 3),
        ])
    }

    func testCaretDollarMatchEmptyLine() throws {
        let buffer = DocumentBuffer(text: "foo\n\nbar")
        let matches = try TextSearcher.allMatches(in: buffer, query: "^$", useRegex: true, caseSensitive: true)
        XCTAssertEqual(matches, [SearchMatch(line: 1, startColumn: 0, endColumn: 0)])
    }

    func testAnchoredPatternWithContentStillMatchesNormally() throws {
        let buffer = DocumentBuffer(text: "foo\nfoobar\nbarfoo")
        let matches = try TextSearcher.allMatches(in: buffer, query: "^foo", useRegex: true, caseSensitive: true)
        XCTAssertEqual(matches, [
            SearchMatch(line: 0, startColumn: 0, endColumn: 3),
            SearchMatch(line: 1, startColumn: 0, endColumn: 3),
        ])
    }
}
