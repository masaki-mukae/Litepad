import XCTest
@testable import Litepad

final class SelectionStatusFormatterTests: XCTestCase {
    func testNoSelectionReturnsEmptyString() {
        let buffer = DocumentBuffer(text: "hello")
        let text = SelectionStatusFormatter.text(
            buffer: buffer,
            selection: nil,
            rectSelection: nil
        )
        XCTAssertEqual(text, "")
    }

    func testCollapsedSelectionReturnsEmptyString() {
        let buffer = DocumentBuffer(text: "hello")
        let cursor = CursorPosition(line: 0, column: 2)
        let text = SelectionStatusFormatter.text(
            buffer: buffer,
            selection: (cursor, cursor),
            rectSelection: nil
        )
        XCTAssertEqual(text, "")
    }

    func testSingleLineAsciiSelectionShowsSameCharAndByteCount() {
        let buffer = DocumentBuffer(text: "hello world")
        let text = SelectionStatusFormatter.text(
            buffer: buffer,
            selection: (CursorPosition(line: 0, column: 0), CursorPosition(line: 0, column: 5)),
            rectSelection: nil
        )
        XCTAssertEqual(text, "5文字/5バイト選択中")
    }

    func testSingleLineMultibyteSelectionShowsDifferentCharAndByteCount() {
        // "あ"はUTF-8で3バイト。
        let buffer = DocumentBuffer(text: "あいう", encoding: .utf8)
        let text = SelectionStatusFormatter.text(
            buffer: buffer,
            selection: (CursorPosition(line: 0, column: 0), CursorPosition(line: 0, column: 2)),
            rectSelection: nil
        )
        XCTAssertEqual(text, "2文字/6バイト選択中")
    }

    func testMultiLineSelectionIncludesLineCount() {
        let buffer = DocumentBuffer(text: "abc\ndef\nghi")
        let text = SelectionStatusFormatter.text(
            buffer: buffer,
            selection: (CursorPosition(line: 0, column: 1), CursorPosition(line: 2, column: 2)),
            rectSelection: nil
        )
        // 1行目: "bc\n"(3) + 2行目: "def\n"(4) + 3行目: "gh"(2) = 9文字/9バイト、3行。
        XCTAssertEqual(text, "9文字/9バイト選択中 (3行)")
    }

    func testHugeSelectionAboveLineCapSkipsExactCount() {
        let lines = (0..<(SelectionStatusFormatter.maxLinesForExactCount + 10)).map { "line\($0)" }
        let buffer = DocumentBuffer(text: lines.joined(separator: "\n"))
        let lineCount = SelectionStatusFormatter.maxLinesForExactCount + 5
        let text = SelectionStatusFormatter.text(
            buffer: buffer,
            selection: (CursorPosition(line: 0, column: 0), CursorPosition(line: lineCount - 1, column: 0)),
            rectSelection: nil
        )
        XCTAssertEqual(text, "\(lineCount)行選択中")
    }

    func testRectSelectionFormat() {
        let buffer = DocumentBuffer(text: "abcdef\nghijkl\nmnopqr")
        let text = SelectionStatusFormatter.text(
            buffer: buffer,
            selection: nil,
            rectSelection: (topLine: 0, bottomLine: 2, leftColumn: 1, rightColumn: 4)
        )
        XCTAssertEqual(text, "3桁 × 3行選択中")
    }

    func testRectSelectionWithZeroWidthReturnsEmptyString() {
        let buffer = DocumentBuffer(text: "abcdef\nghijkl")
        let text = SelectionStatusFormatter.text(
            buffer: buffer,
            selection: nil,
            rectSelection: (topLine: 0, bottomLine: 1, leftColumn: 2, rightColumn: 2)
        )
        XCTAssertEqual(text, "")
    }
}
