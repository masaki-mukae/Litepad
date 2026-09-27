import Foundation

/// 保存/読み込み時に保持する文字コード種別。
enum TextEncodingKind: Equatable, CaseIterable {
    case utf8
    case utf8BOM
    case shiftJIS
    case utf16LE
    case utf16BE

    var displayName: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf8BOM: return "UTF-8 (BOM付き)"
        case .shiftJIS: return "Shift_JIS"
        case .utf16LE: return "UTF-16 (LE)"
        case .utf16BE: return "UTF-16 (BE)"
        }
    }
}

/// 保存/読み込み時に保持する改行コード種別。
enum LineEnding: String {
    case lf = "\n"
    case crlf = "\r\n"
    case cr = "\r"

    var displayName: String {
        switch self {
        case .lf: return "LF"
        case .crlf: return "CRLF"
        case .cr: return "CR"
        }
    }
}

/// ファイル入出力時の文字コード判定・変換。
/// BOMがあれば優先し、なければUTF-8としての妥当性 → Shift_JIS(CP932)の順で判定する。
enum TextFileCodec {
    static let shiftJISEncoding: String.Encoding = {
        let cf = CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)
        let raw = CFStringConvertEncodingToNSStringEncoding(cf)
        return String.Encoding(rawValue: raw)
    }()

    static func decode(_ data: Data) -> (text: String, encoding: TextEncodingKind) {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            let body = data.dropFirst(3)
            return (String(data: body, encoding: .utf8) ?? "", .utf8BOM)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            let body = data.dropFirst(2)
            return (String(data: body, encoding: .utf16LittleEndian) ?? "", .utf16LE)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            let body = data.dropFirst(2)
            return (String(data: body, encoding: .utf16BigEndian) ?? "", .utf16BE)
        }
        if let text = String(data: data, encoding: .utf8) {
            return (text, .utf8)
        }
        if let text = String(data: data, encoding: shiftJISEncoding) {
            return (text, .shiftJIS)
        }
        return (String(decoding: data, as: UTF8.self), .utf8)
    }

    static func encode(_ text: String, as encoding: TextEncodingKind) -> Data {
        bomPrefix(for: encoding) + encodeLineContent(text, as: encoding)
    }

    static func bomPrefix(for encoding: TextEncodingKind) -> Data {
        switch encoding {
        case .utf8BOM: return Data([0xEF, 0xBB, 0xBF])
        case .utf16LE: return Data([0xFF, 0xFE])
        case .utf16BE: return Data([0xFE, 0xFF])
        case .utf8, .shiftJIS: return Data()
        }
    }

    /// BOMを含まない、1行分（または任意のテキスト片）のバイト列を返す。
    static func encodeLineContent(_ text: String, as encoding: TextEncodingKind) -> Data {
        switch encoding {
        case .utf8, .utf8BOM:
            return Data(text.utf8)
        case .shiftJIS:
            return text.data(using: shiftJISEncoding) ?? Data(text.utf8)
        case .utf16LE:
            return text.data(using: .utf16LittleEndian) ?? Data()
        case .utf16BE:
            return text.data(using: .utf16BigEndian) ?? Data()
        }
    }

    /// 本家サクラエディタの文字コード自動判定（`CFileLoad`の`m_nAutoDetectReadLen`）に
    /// 倣い、ファイル全体ではなく先頭32KBだけをサンプルとして判定する。巨大ファイルを
    /// 開くたびに数百MB〜GB単位を全走査するのは、行インデックス作成とは別に発生する
    /// 無駄なオーバーヘッドであり、通常のテキストファイルは冒頭だけで文字コードの
    /// 判別には十分なため。
    private static let autoDetectSampleSize = 32 * 1024

    /// BOMだけを見て文字コードを判定し、本文の開始バイト位置（BOMを除いた範囲）を返す。
    /// BOMが無い場合は先頭サンプルのUTF-8としての妥当性を検証し、妥当でなければ
    /// 同じサンプルをShift_JISとして解釈できるか試す。
    static func detectEncoding(_ data: Data) -> (encoding: TextEncodingKind, bodyRange: Range<Int>) {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return (.utf8BOM, 3..<data.count) }
        if data.starts(with: [0xFF, 0xFE]) { return (.utf16LE, 2..<data.count) }
        if data.starts(with: [0xFE, 0xFF]) { return (.utf16BE, 2..<data.count) }
        let sample = data.prefix(autoDetectSampleSize)
        if isValidUTF8(sample) { return (.utf8, 0..<data.count) }
        if String(data: sample, encoding: shiftJISEncoding) != nil {
            return (.shiftJIS, 0..<data.count)
        }
        return (.utf8, 0..<data.count)
    }

    /// サンプルを文字列として実体化せずに、UTF-8として妥当かどうかを生ポインタで判定する。
    /// `Data`のイテレータはバウンドチェック付きで低速なため、`UnsafeBufferPointer`経由にする。
    private static func isValidUTF8(_ sample: Data) -> Bool {
        sample.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            let buffer = raw.bindMemory(to: UInt8.self)
            var decoder = UTF8()
            var iterator = buffer.makeIterator()
            while true {
                switch decoder.decode(&iterator) {
                case .scalarValue: continue
                case .emptyInput: return true
                case .error: return false
                }
            }
        }
    }

    /// 指定範囲のバイト列を、判定済みの文字コードで1行分としてデコードする。
    static func decodeLine(_ data: Data, encoding: TextEncodingKind) -> String {
        switch encoding {
        case .utf8, .utf8BOM:
            return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        case .shiftJIS:
            return String(data: data, encoding: shiftJISEncoding) ?? String(decoding: data, as: UTF8.self)
        case .utf16LE:
            return String(data: data, encoding: .utf16LittleEndian) ?? ""
        case .utf16BE:
            return String(data: data, encoding: .utf16BigEndian) ?? ""
        }
    }
}
