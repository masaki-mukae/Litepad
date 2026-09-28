import XCTest
@testable import Litepad

final class SelectionStatusFormatterTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

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

    /// 上限（200万行）ぎりぎりまで、mmap経由の未実体化行に対して計算しても高速であること
    /// （`DocumentBuffer.peekLine`/`lineByteLength`がデコードを避けているかの回帰テスト）。
    /// `DocumentBuffer(text:)`（インメモリ）ではなく`DocumentBuffer(contentsOf:)`（mmap＋遅延
    /// デコード）で実ファイルから読み込むのが重要: 前者は生成時に全行を実体化してしまうため、
    /// この最適化が効いているかを検証できない。
    func testExactCountNearRaisedCapStaysFastOnUnmaterializedLines() throws {
        let n = 1_900_000
        var content = ""
        content.reserveCapacity(n * 12)
        for i in 0..<n { content += "line \(i) サンプル\n" }
        let url = tempDir.appendingPathComponent("huge.txt")
        try content.write(to: url, atomically: true, encoding: .utf8)

        let buffer = try DocumentBuffer(contentsOf: url)
        XCTAssertLessThan(n, SelectionStatusFormatter.maxLinesForExactCount, "この検証には上限未満の行数が必要")

        let start = Date()
        let text = SelectionStatusFormatter.text(
            buffer: buffer,
            selection: (CursorPosition(line: 0, column: 0), CursorPosition(line: n - 1, column: 0)),
            rectSelection: nil
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(text.contains("文字/") && text.contains("バイト選択中"), "上限未満なので実際の文字数/バイト数が出るはず: \(text)")
        // デコードを伴う旧実装なら190万行の全文字列化で数秒かかるはず。
        // デコード不要のバイト長読み取り+デコードのみの文字数カウントなら数百ms程度で終わる。
        XCTAssertLessThan(elapsed, 3.0, "選択範囲のバイト数/文字数計算が遅すぎる(所要時間: \(elapsed)秒)")
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
