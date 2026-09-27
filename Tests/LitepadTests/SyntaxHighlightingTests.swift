import XCTest
@testable import Litepad

final class SyntaxHighlightingTests: XCTestCase {
    func testLanguageDetectionByExtension() {
        XCTAssertNotNil(LanguageDefinition.detect(forExtension: "swift"))
        XCTAssertNotNil(LanguageDefinition.detect(forExtension: "PY"), "拡張子の大文字小文字を無視する")
        XCTAssertNotNil(LanguageDefinition.detect(forExtension: "cob"))
        XCTAssertNil(LanguageDefinition.detect(forExtension: "unknownext"))
    }

    private func kinds(_ tokens: [SyntaxToken]) -> [SyntaxTokenKind] { tokens.map(\.kind) }

    func testCLikeKeywordStringCommentNumber() {
        let language = LanguageDefinition.cLikeModern
        let (tokens, endState) = SyntaxHighlighter.tokenize(
            line: #"if (x == 42) { s = "hi"; } // comment"#,
            startState: .normal,
            language: language
        )
        XCTAssertTrue(kinds(tokens).contains(.keyword))
        XCTAssertTrue(kinds(tokens).contains(.number))
        XCTAssertTrue(kinds(tokens).contains(.doubleQuoteString))
        XCTAssertTrue(kinds(tokens).contains(.comment))
        XCTAssertEqual(endState, .normal, "行コメントは行末で終わるので継続状態は残らない")
    }

    func testBlockCommentContinuesAcrossLines() {
        let language = LanguageDefinition.cLikeModern
        let (_, stateAfterOpen) = SyntaxHighlighter.tokenize(
            line: "/* start of comment",
            startState: .normal,
            language: language
        )
        guard case .blockComment = stateAfterOpen else {
            return XCTFail("ブロックコメント開始後は.blockCommentになるはず: \(stateAfterOpen)")
        }

        let (middleTokens, stateStillOpen) = SyntaxHighlighter.tokenize(
            line: "still inside comment",
            startState: stateAfterOpen,
            language: language
        )
        XCTAssertEqual(kinds(middleTokens), [.comment])
        guard case .blockComment = stateStillOpen else {
            return XCTFail("2行目もコメント継続中のはず")
        }

        let (_, stateAfterClose) = SyntaxHighlighter.tokenize(
            line: "end */ int x = 1;",
            startState: stateStillOpen,
            language: language
        )
        XCTAssertEqual(stateAfterClose, .normal, "閉じタグの後は通常状態に戻る")
    }

    func testPythonTripleQuoteStringSpansLines() {
        let language = LanguageDefinition.python
        let (_, stateAfterOpen) = SyntaxHighlighter.tokenize(
            line: #"x = """start of docstring"#,
            startState: .normal,
            language: language
        )
        guard case .tripleQuoteString = stateAfterOpen else {
            return XCTFail("triple-quoteの開始後は.tripleQuoteStringになるはず: \(stateAfterOpen)")
        }

        let (_, stateAfterClose) = SyntaxHighlighter.tokenize(
            line: #"end of docstring""""#,
            startState: stateAfterOpen,
            language: language
        )
        XCTAssertEqual(stateAfterClose, .normal)
    }

    func testPythonColonTriggersIndentFlag() {
        XCTAssertTrue(LanguageDefinition.python.colonTriggersIndent)
        XCTAssertFalse(LanguageDefinition.cLikeModern.colonTriggersIndent)
    }

    func testCobolFixedColumnComment() {
        let language = LanguageDefinition.cobol
        XCTAssertEqual(language.fixedColumnCommentColumn, 6, "COBOLは7桁目(0-indexedで6)がコメントマーカー列")
        // 7桁目(index 6)に'*'があると行全体がコメット扱いになる。
        let line = "      *this whole line is a comment"
        let (tokens, _) = SyntaxHighlighter.tokenize(line: line, startState: .normal, language: language)
        XCTAssertEqual(kinds(tokens), [.comment])
    }

    func testSingleVsDoubleQuoteStringsAreDistinctColors() {
        let language = LanguageDefinition.cLikeModern
        let (tokens, _) = SyntaxHighlighter.tokenize(line: #"'a' "b""#, startState: .normal, language: language)
        XCTAssertTrue(kinds(tokens).contains(.singleQuoteString))
        XCTAssertTrue(kinds(tokens).contains(.doubleQuoteString))
    }

    // MARK: - URL検出（言語非依存）

    func testURLDetectionIsLanguageIndependent() {
        let ranges = SyntaxHighlighter.urlRanges(in: "see https://example.com/path for details")
        XCTAssertEqual(ranges.count, 1)
        let range = ranges[0]
        let chars = Array("see https://example.com/path for details")
        XCTAssertEqual(String(chars[range]), "https://example.com/path")
    }

    func testNoURLReturnsEmpty() {
        XCTAssertTrue(SyntaxHighlighter.urlRanges(in: "no links here").isEmpty)
    }
}
