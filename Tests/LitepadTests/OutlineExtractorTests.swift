import XCTest
@testable import Litepad

final class OutlineExtractorTests: XCTestCase {
    func testSwiftExtractsTypesAndFunctions() {
        let buffer = DocumentBuffer(text: """
        import Foundation

        struct Point {
            var x: Int
        }

        class Renderer {
            func draw() {
                print("drawing")
            }

            func clear() {}
        }
        """)
        let items = OutlineExtractor.extract(from: buffer, fileExtension: "swift")
        XCTAssertEqual(items.map(\.title), ["struct Point", "class Renderer", "func draw", "func clear"])
        XCTAssertEqual(items.first(where: { $0.title == "class Renderer" })?.line, 6)
    }

    func testSwiftIndentReflectsSourceIndentation() {
        let buffer = DocumentBuffer(text: "class Outer {\n    func inner() {}\n}")
        let items = OutlineExtractor.extract(from: buffer, fileExtension: "swift")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].indent, 0)
        XCTAssertEqual(items[1].indent, 4)
    }

    func testDoesNotFalsePositiveOnIdentifierPrefix() {
        // "classify" は "class" というキーワードの一部ではなく、識別子の先頭一致に過ぎない。
        let buffer = DocumentBuffer(text: "func classify() {}\nlet classroom = 1")
        let items = OutlineExtractor.extract(from: buffer, fileExtension: "swift")
        XCTAssertEqual(items.map(\.title), ["func classify"])
    }

    func testPythonDefAndClass() {
        let buffer = DocumentBuffer(text: """
        class Animal:
            def speak(self):
                pass

        def main():
            pass
        """)
        let items = OutlineExtractor.extract(from: buffer, fileExtension: "py")
        XCTAssertEqual(items.map(\.title), ["class Animal", "def speak", "def main"])
    }

    func testGoFuncAndType() {
        let buffer = DocumentBuffer(text: "type Server struct {\n}\n\nfunc Start() {\n}")
        let items = OutlineExtractor.extract(from: buffer, fileExtension: "go")
        XCTAssertEqual(items.map(\.title), ["type Server", "func Start"])
    }

    func testRustFnStructEnumTrait() {
        let buffer = DocumentBuffer(text: "struct Foo {}\nenum Bar {}\ntrait Baz {}\nfn run() {}")
        let items = OutlineExtractor.extract(from: buffer, fileExtension: "rs")
        XCTAssertEqual(items.map(\.title), ["struct Foo", "enum Bar", "trait Baz", "fn run"])
    }

    func testCTypesOnlyNoFalseFunctionDetection() {
        // C/C++には関数専用キーワードが無いため、型宣言のみ抽出対象。
        let buffer = DocumentBuffer(text: "class Widget {\npublic:\n    void draw();\n};\nint main() { return 0; }")
        let items = OutlineExtractor.extract(from: buffer, fileExtension: "cpp")
        XCTAssertEqual(items.map(\.title), ["class Widget"])
    }

    func testJavaTypesOnly() {
        let buffer = DocumentBuffer(text: "public class Foo {\n    interface Bar {}\n    enum Baz { A, B }\n}")
        let items = OutlineExtractor.extract(from: buffer, fileExtension: "java")
        XCTAssertEqual(items.map(\.title), ["class Foo", "interface Bar", "enum Baz"])
    }

    func testVisibilityModifiersBeforeKeywordAreSkipped() {
        // 可視性修飾子(public/private等)が前に付く実際のコードでも正しく拾えることを確認する。
        let buffer = DocumentBuffer(text: "public final class Foo {}\nprivate struct Bar {}")
        let items = OutlineExtractor.extract(from: buffer, fileExtension: "swift")
        XCTAssertEqual(items.map(\.title), ["class Foo", "struct Bar"])
    }

    func testKeywordInsideCallExpressionIsIgnored() {
        // 括弧の中（呼び出し式の一部）にキーワードらしき語があっても誤検出しない。
        let buffer = DocumentBuffer(text: "foo(class: Bar.class)")
        let items = OutlineExtractor.extract(from: buffer, fileExtension: "java")
        XCTAssertTrue(items.isEmpty)
    }

    func testPascalCaseInsensitiveKeywords() {
        let buffer = DocumentBuffer(text: "PROCEDURE DoThing;\nFUNCTION Compute: Integer;")
        let items = OutlineExtractor.extract(from: buffer, fileExtension: "pas")
        XCTAssertEqual(items.map(\.title), ["procedure DoThing", "function Compute"])
    }

    func testVisualBasicSubAndFunction() {
        let buffer = DocumentBuffer(text: "Public Sub DoWork()\nEnd Sub\nFunction Add(a, b)\nEnd Function")
        let items = OutlineExtractor.extract(from: buffer, fileExtension: "vb")
        XCTAssertEqual(items.map(\.title), ["Sub DoWork", "Function Add"])
    }

    func testPerlSub() {
        let buffer = DocumentBuffer(text: "sub greet {\n    print \"hi\";\n}")
        let items = OutlineExtractor.extract(from: buffer, fileExtension: "pl")
        XCTAssertEqual(items.map(\.title), ["sub greet"])
    }

    func testSQLCreateStatements() {
        let buffer = DocumentBuffer(text: "CREATE TABLE users (id INT);\ncreate procedure DoStuff\nCREATE VIEW active_users AS SELECT 1")
        let items = OutlineExtractor.extract(from: buffer, fileExtension: "sql")
        XCTAssertEqual(items.map(\.title), ["TABLE users", "PROCEDURE DoStuff", "VIEW active_users"])
    }

    func testTeXSectionsWithNestingLevels() {
        let buffer = DocumentBuffer(text: "\\chapter{Intro}\n\\section{Background}\n\\subsection{Details}\nsome text\n\\section{Next}")
        let items = OutlineExtractor.extract(from: buffer, fileExtension: "tex")
        XCTAssertEqual(items.map(\.title), ["Intro", "Background", "Details", "Next"])
        XCTAssertEqual(items.map(\.indent), [0, 4, 8, 4])
    }

    func testUnsupportedExtensionReturnsEmpty() {
        let buffer = DocumentBuffer(text: "class Foo {}")
        XCTAssertTrue(OutlineExtractor.extract(from: buffer, fileExtension: "ini").isEmpty)
        XCTAssertTrue(OutlineExtractor.extract(from: buffer, fileExtension: "unknownext").isEmpty)
    }

    func testEmptyFileReturnsEmpty() {
        let buffer = DocumentBuffer(text: "")
        XCTAssertTrue(OutlineExtractor.extract(from: buffer, fileExtension: "swift").isEmpty)
    }
}
