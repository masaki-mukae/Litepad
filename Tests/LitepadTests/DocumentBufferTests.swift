import XCTest
@testable import Litepad

/// `DocumentBuffer`（内部は`LineStore`のmmap＋ブロック分割行インデックス）の正しさを検証する。
/// このファイルは今回のセッション中に何度もスタンドアロンスクリプトとして書いては捨てていた
/// 検証内容を、恒久的な自動テストとして固定化したもの。
final class DocumentBufferTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ content: String, named name: String = "test.txt", encoding: String.Encoding = .utf8) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try content.data(using: encoding)!.write(to: url)
        return url
    }

    // MARK: - 基本往復

    func testBasicRoundTripAfterEdit() throws {
        let url = try write("line1\nline2\nline3")
        let buf = try DocumentBuffer(contentsOf: url)
        XCTAssertEqual(buf.lineCount, 3)
        XCTAssertEqual(buf.line(at: 1), "line2")

        buf.replaceLine(1, with: "LINE2-EDITED")
        try buf.write(to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "line1\nLINE2-EDITED\nline3")
    }

    func testEmptyFile() throws {
        let url = try write("")
        let buf = try DocumentBuffer(contentsOf: url)
        XCTAssertEqual(buf.lineCount, 1)
        XCTAssertEqual(buf.line(at: 0), "")
    }

    func testNewInMemoryDocumentSavesCorrectly() throws {
        let url = tempDir.appendingPathComponent("new.txt")
        let buf = DocumentBuffer(text: "hello\nworld")
        try buf.write(to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "hello\nworld")
    }

    // MARK: - 改行コード

    func testCRLFDetectionAndPreservation() throws {
        let url = try write("a\r\nb\r\nc\r\n")
        let buf = try DocumentBuffer(contentsOf: url)
        XCTAssertEqual(buf.lineCount, 4, "末尾の改行により空行が1つ増える")
        XCTAssertEqual(buf.lineEnding, .crlf)
        XCTAssertEqual(buf.line(at: 0), "a")
        XCTAssertEqual(buf.line(at: 2), "c")

        try buf.write(to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "a\r\nb\r\nc\r\n", "未編集ファイルはバイト単位で不変のはず")
    }

    // MARK: - 文字コード判定

    func testUTF8BOMRoundTrip() throws {
        let url = tempDir.appendingPathComponent("bom.txt")
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("こんにちは\n世界".data(using: .utf8)!)
        try data.write(to: url)

        let buf = try DocumentBuffer(contentsOf: url)
        XCTAssertEqual(buf.encoding, .utf8BOM)
        XCTAssertEqual(buf.line(at: 0), "こんにちは")
        XCTAssertEqual(buf.line(at: 1), "世界")

        try buf.write(to: url)
        let raw = try Data(contentsOf: url)
        XCTAssertEqual(Array(raw.prefix(3)), [0xEF, 0xBB, 0xBF], "保存後もBOMが維持される")
    }

    func testShiftJISDetection() throws {
        let url = tempDir.appendingPathComponent("sjis.txt")
        let data = "日本語テスト\n二行目".data(using: TextFileCodec.shiftJISEncoding)!
        try data.write(to: url)

        let buf = try DocumentBuffer(contentsOf: url)
        XCTAssertEqual(buf.encoding, .shiftJIS)
        XCTAssertEqual(buf.line(at: 0), "日本語テスト")
        XCTAssertEqual(buf.line(at: 1), "二行目")
    }

    // MARK: - 文字コード変換

    /// 一度も読んでいない（＝未実体化の）行を含むファイルをShift_JISからUTF-8へ変換した場合、
    /// 元のバイト列を「変換前の」エンコーディングで正しくデコードしてから切り替える必要がある。
    /// 先に切り替えてしまうと、Shift_JISの生バイト列をUTF-8として誤って解釈し文字化けする。
    func testConvertEncodingOnUnmaterializedLinesPreservesContent() throws {
        let url = tempDir.appendingPathComponent("sjis.txt")
        let data = "日本語テスト\n二行目\n三行目".data(using: TextFileCodec.shiftJISEncoding)!
        try data.write(to: url)

        let buf = try DocumentBuffer(contentsOf: url)
        XCTAssertEqual(buf.encoding, .shiftJIS)
        // まだ1行も`line(at:)`していない＝未実体化のまま変換する。

        buf.reassignEncoding(.utf8)
        XCTAssertEqual(buf.encoding, .utf8)
        XCTAssertEqual(buf.line(at: 0), "日本語テスト", "変換後も内容は変わらない")
        XCTAssertEqual(buf.line(at: 1), "二行目")
        XCTAssertEqual(buf.line(at: 2), "三行目")

        try buf.write(to: url)
        let saved = try Data(contentsOf: url)
        XCTAssertEqual(String(data: saved, encoding: .utf8), "日本語テスト\n二行目\n三行目", "保存後のバイト列はUTF-8になっている")
    }

    func testConvertEncodingToUTF8BOMAddsBOMOnSave() throws {
        let buf = DocumentBuffer(text: "hello")
        buf.reassignEncoding(.utf8BOM)
        let url = tempDir.appendingPathComponent("bom-out.txt")
        try buf.write(to: url)
        let raw = try Data(contentsOf: url)
        XCTAssertEqual(Array(raw.prefix(3)), [0xEF, 0xBB, 0xBF])
    }

    func testConvertEncodingToSameEncodingIsNoOp() throws {
        let url = try write("hello", encoding: .utf8)
        let buf = try DocumentBuffer(contentsOf: url)
        buf.reassignEncoding(.utf8)
        XCTAssertEqual(buf.encoding, .utf8)
        XCTAssertEqual(buf.line(at: 0), "hello")
    }

    // MARK: - 基本編集操作

    func testInsertAndDeleteBackwardMergesLines() {
        let buf = DocumentBuffer(text: "hello world")
        var pos = CursorPosition(line: 0, column: 5)
        pos = buf.insertNewline(at: pos)
        XCTAssertEqual(buf.lineCount, 2)
        XCTAssertEqual(buf.line(at: 0), "hello")
        XCTAssertEqual(buf.line(at: 1), " world")

        pos = buf.deleteBackward(at: pos)
        XCTAssertEqual(buf.lineCount, 1)
        XCTAssertEqual(buf.line(at: 0), "hello world")
        XCTAssertEqual(pos, CursorPosition(line: 0, column: 5))
    }

    // MARK: - 複数ブロックにまたがる巨大行数ファイル（LineStoreのブロック分割を強制する）

    private let targetBlockSize = 4096 // LineStore.targetBlockSizeと同じ値。複数ブロックを強制するため。

    func testSequentialAndRandomAccessAcrossManyBlocks() throws {
        let n = 20_000 // targetBlockSizeを大きく超え、複数ブロックが作られる
        var content = ""
        content.reserveCapacity(n * 8)
        for i in 0..<n { content += "row\(i)\n" }
        let url = try write(content)
        let buf = try DocumentBuffer(contentsOf: url)
        XCTAssertEqual(buf.lineCount, n + 1)

        for i in stride(from: 0, to: n, by: 997) {
            XCTAssertEqual(buf.line(at: i), "row\(i)", "逐次/局所アクセス i=\(i)")
        }
        for i in [0, n - 1, n / 2, 1, n - 2] {
            XCTAssertEqual(buf.line(at: i), "row\(i)", "ランダムアクセス i=\(i)")
        }
    }

    func testEditsNearHeadOfHugeFileDoNotCorruptTailOrTakeTooLong() throws {
        let n = 50_000
        var content = ""
        content.reserveCapacity(n * 6)
        for i in 0..<n { content += "L\(i)\n" }
        let url = try write(content)
        let buf = try DocumentBuffer(contentsOf: url)

        let start = Date()
        for _ in 0..<500 {
            var pos = CursorPosition(line: 10, column: 2)
            pos = buf.insertNewline(at: pos)
            _ = buf.deleteBackward(at: pos)
        }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(buf.lineCount, n + 1)
        XCTAssertEqual(buf.line(at: 0), "L0")
        XCTAssertEqual(buf.line(at: 10), "L10")
        XCTAssertEqual(buf.line(at: n - 1), "L\(n - 1)")
        // フラットな配列(O(n)実装)なら5万行×500回で数秒〜数十秒かかるはず。
        // ブロック分割(O(blockSize))であれば1秒未満で終わる。
        XCTAssertLessThan(elapsed, 2.0, "先頭付近への編集がO(n)に戻っていないか(所要時間: \(elapsed)秒)")
    }

    func testManyInsertsForceBlockSplits() {
        let buf = DocumentBuffer(text: "start")
        var pos = CursorPosition(line: 0, column: 5)
        let count = targetBlockSize * 3 // 複数回のブロック分割を確実に誘発する
        for i in 0..<count {
            pos = buf.insertNewline(at: pos)
            for ch in "x\(i)" { pos = buf.insert(ch, at: pos) }
        }
        XCTAssertEqual(buf.lineCount, count + 1)
        XCTAssertEqual(buf.line(at: 0), "start")
        XCTAssertEqual(buf.line(at: 1), "x0")
        XCTAssertEqual(buf.line(at: count / 2), "x\(count / 2 - 1)")
        XCTAssertEqual(buf.line(at: count), "x\(count - 1)")
    }

    func testLargeMultiBlockRangeDeleteForcesBlockMerges() throws {
        let n = 100_000
        var content = ""
        content.reserveCapacity(n * 6)
        for i in 0..<n { content += "M\(i)\n" }
        let url = try write(content)
        let buf = try DocumentBuffer(contentsOf: url)

        // 行1000〜90000を範囲削除(複数ブロックにまたがる大きな削除、併合を誘発する)
        let deleted = buf.deleteRange(
            from: CursorPosition(line: 1000, column: 0),
            to: CursorPosition(line: 90000, column: 0)
        )
        XCTAssertEqual(deleted, CursorPosition(line: 1000, column: 0))
        XCTAssertEqual(buf.lineCount, n + 1 - 89000)
        XCTAssertEqual(buf.line(at: 999), "M999")
        XCTAssertEqual(buf.line(at: 1000), "M90000", "削除範囲の前後がマージされた行")
        XCTAssertEqual(buf.line(at: buf.lineCount - 1), "", "末尾の空行")
        XCTAssertEqual(buf.line(at: buf.lineCount - 2), "M\(n - 1)")
    }

    // MARK: - 保存（連続run検出・ブロック境界をまたぐコピースルー）

    func testFullyUneditedMultiBlockFileIsByteIdenticalAfterSave() throws {
        let n = 30_000
        var content = ""
        content.reserveCapacity(n * 8)
        for i in 0..<n { content += "row-\(i)\n" }
        let url = try write(content)
        let original = try Data(contentsOf: url)

        let buf = try DocumentBuffer(contentsOf: url)
        try buf.write(to: url)

        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testSaveWithEditsCrossingBlockBoundary() throws {
        let n = 30_000
        var content = ""
        for i in 0..<n { content += "row-\(i)\n" }
        let url = try write(content)
        let buf = try DocumentBuffer(contentsOf: url)

        buf.replaceLine(0, with: "EDIT-A")
        buf.replaceLine(targetBlockSize - 1, with: "EDIT-B") // ブロック境界の直前
        buf.replaceLine(targetBlockSize, with: "EDIT-C") // 次のブロックの先頭
        buf.replaceLine(n, with: "EDIT-E") // 最終行
        try buf.write(to: url)

        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "EDIT-A")
        XCTAssertEqual(lines[1], "row-1", "未編集行はコピースルーされる")
        XCTAssertEqual(lines[targetBlockSize - 1], "EDIT-B")
        XCTAssertEqual(lines[targetBlockSize], "EDIT-C")
        XCTAssertEqual(lines[targetBlockSize + 1], "row-\(targetBlockSize + 1)")
        XCTAssertEqual(lines[n], "EDIT-E")
        XCTAssertEqual(lines.count, n + 1)
    }

    func testSaveStreamsAcrossChunkBoundaryWithoutCorruption() throws {
        // LineStore.write内の1MBチャンク境界を跨ぐサイズの未編集領域を作る。
        let line = "0123456789ABCDEF\n" // 17 bytes
        let count = 200_000 // ~3.4MB
        var content = ""
        content.reserveCapacity(count * line.count)
        for _ in 0..<count { content += line }
        let url = try write(content)
        let buf = try DocumentBuffer(contentsOf: url)

        buf.replaceLine(100, with: "PATCH-A")
        buf.replaceLine(150_000, with: "PATCH-B")
        try buf.write(to: url)

        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        XCTAssertEqual(lines.count, count + 1)
        XCTAssertEqual(lines[100], "PATCH-A")
        XCTAssertEqual(lines[150_000], "PATCH-B")
        XCTAssertEqual(lines[99], "0123456789ABCDEF")
    }

    // MARK: - 範囲取得・矩形編集

    func testTextAndDeleteRangeAcrossLines() {
        let buf = DocumentBuffer(text: "abc\ndef\nghi")
        let text = buf.text(from: CursorPosition(line: 0, column: 1), to: CursorPosition(line: 2, column: 2))
        XCTAssertEqual(text, "bc\ndef\ngh")

        let pos = buf.deleteRange(from: CursorPosition(line: 0, column: 1), to: CursorPosition(line: 2, column: 2))
        XCTAssertEqual(pos, CursorPosition(line: 0, column: 1))
        XCTAssertEqual(buf.lineCount, 1)
        XCTAssertEqual(buf.line(at: 0), "ai")
    }

    func testRectTextDeleteAndInsert() {
        let buf = DocumentBuffer(text: "aaaa\nbbbb\ncccc")
        XCTAssertEqual(buf.rectText(topLine: 0, bottomLine: 2, leftColumn: 1, rightColumn: 3), "aa\nbb\ncc")

        buf.deleteRect(topLine: 0, bottomLine: 2, leftColumn: 1, rightColumn: 3)
        XCTAssertEqual(buf.line(at: 0), "aa")
        XCTAssertEqual(buf.line(at: 1), "bb")
        XCTAssertEqual(buf.line(at: 2), "cc")

        buf.insertRect("XY", topLine: 0, bottomLine: 2, column: 1)
        XCTAssertEqual(buf.line(at: 0), "aXYa")
        XCTAssertEqual(buf.line(at: 1), "bXYb")
        XCTAssertEqual(buf.line(at: 2), "cXYc")
    }
}
