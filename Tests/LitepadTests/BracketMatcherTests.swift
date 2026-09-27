import XCTest
@testable import Litepad

final class BracketMatcherTests: XCTestCase {
    func testMatchesOpeningParenForward() {
        let buffer = DocumentBuffer(text: "foo(bar)")
        let cursor = CursorPosition(line: 0, column: 3) // "(" 自体の位置
        let match = BracketMatcher.matchingPositions(in: buffer, cursor: cursor)
        XCTAssertEqual(match?.0, cursor)
        XCTAssertEqual(match?.1, CursorPosition(line: 0, column: 7)) // ")"の位置
    }

    func testMatchesClosingParenBackward() {
        let buffer = DocumentBuffer(text: "foo(bar)")
        let cursor = CursorPosition(line: 0, column: 8) // ")"の直後
        let match = BracketMatcher.matchingPositions(in: buffer, cursor: cursor)
        XCTAssertEqual(match?.0, CursorPosition(line: 0, column: 7))
        XCTAssertEqual(match?.1, CursorPosition(line: 0, column: 3))
    }

    func testNestedBrackets() {
        let buffer = DocumentBuffer(text: "a(b(c)d)e")
        // 最初の "(" (index 1) は対応する最後の ")" (index 7) と対応する
        let outer = BracketMatcher.matchingPositions(in: buffer, cursor: CursorPosition(line: 0, column: 1))
        XCTAssertEqual(outer?.1, CursorPosition(line: 0, column: 7))

        // 内側の "(" (index 3) は内側の ")" (index 5) と対応する
        let inner = BracketMatcher.matchingPositions(in: buffer, cursor: CursorPosition(line: 0, column: 3))
        XCTAssertEqual(inner?.1, CursorPosition(line: 0, column: 5))
    }

    func testDifferentBracketKinds() {
        let buffer = DocumentBuffer(text: "[a{b}c]")
        let square = BracketMatcher.matchingPositions(in: buffer, cursor: CursorPosition(line: 0, column: 0))
        XCTAssertEqual(square?.1, CursorPosition(line: 0, column: 6))

        let curly = BracketMatcher.matchingPositions(in: buffer, cursor: CursorPosition(line: 0, column: 2))
        XCTAssertEqual(curly?.1, CursorPosition(line: 0, column: 4))
    }

    func testUnmatchedBracketReturnsNil() {
        let buffer = DocumentBuffer(text: "foo(bar")
        let match = BracketMatcher.matchingPositions(in: buffer, cursor: CursorPosition(line: 0, column: 3))
        XCTAssertNil(match)
    }

    func testNoBracketAtCursorReturnsNil() {
        let buffer = DocumentBuffer(text: "foo(bar)")
        let match = BracketMatcher.matchingPositions(in: buffer, cursor: CursorPosition(line: 0, column: 0))
        XCTAssertNil(match)
    }

    func testMatchAcrossMultipleLines() {
        let buffer = DocumentBuffer(text: "func f() {\n    print(1)\n}")
        // 1行目の "{" (index 9) は3行目の "}" と対応する
        let match = BracketMatcher.matchingPositions(in: buffer, cursor: CursorPosition(line: 0, column: 9))
        XCTAssertEqual(match?.1, CursorPosition(line: 2, column: 0))
    }

    func testFindOpeningForPendingClose() {
        let buffer = DocumentBuffer(text: "if true {\n    ")
        // 2行目の末尾(column 4)に "}" を今から挿入すると仮定した場合、1行目の "{" と対応するはず
        let opening = BracketMatcher.findOpeningForPendingClose(
            in: buffer,
            cursor: CursorPosition(line: 1, column: 4),
            open: "{",
            close: "}"
        )
        XCTAssertEqual(opening, CursorPosition(line: 0, column: 8))
    }
}
