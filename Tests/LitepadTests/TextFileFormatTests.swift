import XCTest
@testable import Litepad

final class TextFileFormatTests: XCTestCase {
    func testDetectEncodingUTF8BOM() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("hello".data(using: .utf8)!)
        let (encoding, bodyRange) = TextFileCodec.detectEncoding(data)
        XCTAssertEqual(encoding, .utf8BOM)
        XCTAssertEqual(bodyRange, 3..<data.count)
    }

    func testDetectEncodingUTF16LEBOM() {
        var data = Data([0xFF, 0xFE])
        data.append("hi".data(using: .utf16LittleEndian)!)
        let (encoding, bodyRange) = TextFileCodec.detectEncoding(data)
        XCTAssertEqual(encoding, .utf16LE)
        XCTAssertEqual(bodyRange, 2..<data.count)
    }

    func testDetectEncodingUTF16BEBOM() {
        var data = Data([0xFE, 0xFF])
        data.append("hi".data(using: .utf16BigEndian)!)
        let (encoding, bodyRange) = TextFileCodec.detectEncoding(data)
        XCTAssertEqual(encoding, .utf16BE)
        XCTAssertEqual(bodyRange, 2..<data.count)
    }

    func testDetectEncodingPlainUTF8NoBOM() {
        let data = "普通のUTF-8テキスト".data(using: .utf8)!
        let (encoding, bodyRange) = TextFileCodec.detectEncoding(data)
        XCTAssertEqual(encoding, .utf8)
        XCTAssertEqual(bodyRange, 0..<data.count)
    }

    func testDetectEncodingShiftJISFallback() {
        let data = "日本語テスト".data(using: TextFileCodec.shiftJISEncoding)!
        let (encoding, _) = TextFileCodec.detectEncoding(data)
        XCTAssertEqual(encoding, .shiftJIS)
    }

    /// 本家サクラエディタの自動判定と同じく、先頭32KBだけをサンプルとして判定する仕様。
    /// 先頭32KBが正常なUTF-8であれば、それより後ろに不正なバイト列があってもUTF-8と
    /// 判定される（全文スキャンだった旧実装からの意図的な仕様変更）。
    func testEncodingDetectionIsSampledNotFullScan() {
        var data = Data(repeating: 0x41, count: 40_000) // 先頭40000バイトは妥当なASCII
        data.append(contentsOf: [0xFF, 0xFE, 0xFF]) // 32KBより後ろに不正なUTF-8バイト列
        let (encoding, _) = TextFileCodec.detectEncoding(data)
        XCTAssertEqual(encoding, .utf8, "サンプル範囲外の不正バイトはUTF-8判定に影響しない")
    }

    func testInvalidBytesWithinSampleStillFallBackToShiftJIS() {
        let cf = CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)
        let sjisEnc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        var data = "冒頭からシフトJIS".data(using: sjisEnc)!
        data.append(Data(repeating: 0x42, count: 40_000))
        let (encoding, _) = TextFileCodec.detectEncoding(data)
        XCTAssertEqual(encoding, .shiftJIS, "サンプル範囲内の不正バイトは正しくフォールバックする")
    }

    func testEncodeDecodeRoundTripAllEncodings() {
        let text = "hello 世界 🎉"
        for encoding: TextEncodingKind in [.utf8, .utf8BOM, .shiftJIS, .utf16LE, .utf16BE] {
            let data = TextFileCodec.encode(text, as: encoding)
            let (decoded, _) = TextFileCodec.decode(data)
            XCTAssertEqual(decoded, text, "\(encoding)の往復")
        }
    }

    func testDecodeLineMatchesEncodeLineContent() {
        let text = "テスト行"
        for encoding: TextEncodingKind in [.utf8, .shiftJIS, .utf16LE, .utf16BE] {
            let data = TextFileCodec.encodeLineContent(text, as: encoding)
            XCTAssertEqual(TextFileCodec.decodeLine(data, encoding: encoding), text, "\(encoding)")
        }
    }
}
