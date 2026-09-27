import Foundation

/// mmapされたファイルのバイト列を一度だけ走査し、各行の内容バイト位置（改行文字自身は
/// 含まない）を`starts`（開始位置）/`lengths`（長さ）の列指向配列として作る。この時点では
/// 文字列化は一切行わない（巨大ファイルを開いた瞬間に全行分のStringを作ってしまうと、
/// 遅延ロードの意味がなくなるため）。行数が数千万に達するファイルでも配列そのものが
/// 肥大化しないよう、`Range<Int>`（1行16バイト）ではなくこの2配列（1行12バイト）で持つ。
/// 最初に見つかった改行の種類をファイル全体の改行コードとして返す（見つからなければLF扱い）。
enum LineIndexScanner {
    static func indexLines(
        in data: Data,
        bodyRange: Range<Int>,
        encoding: TextEncodingKind
    ) -> (starts: [UInt64], lengths: [UInt32], lineEnding: LineEnding) {
        switch encoding {
        case .utf16LE:
            return indexLinesUTF16(data, bodyRange: bodyRange, littleEndian: true)
        case .utf16BE:
            return indexLinesUTF16(data, bodyRange: bodyRange, littleEndian: false)
        case .utf8, .utf8BOM, .shiftJIS:
            return indexLinesByteOriented(data, bodyRange: bodyRange)
        }
    }

    /// 行数の見積もり。実際の平均行長より短めの値を使うことで、走査の途中で配列の
    /// 再確保（コピーを伴う）が起きる回数を抑える（過大確保にはならない範囲で）。
    private static func estimatedLineCapacity(for byteCount: Int) -> Int {
        max(16, byteCount / 16)
    }

    // UTF-8 / Shift_JIS(CP932)は改行をASCII範囲の0x0D/0x0Aで表す。CP932の2バイト文字の
    // 後続バイトが0x0D/0x0Aと衝突することは仕様上ないため、単純なバイト走査で安全に行分割できる。
    // CRLF・LF単独・CR単独のいずれの改行コードにも対応する。
    private static func indexLinesByteOriented(
        _ data: Data,
        bodyRange: Range<Int>
    ) -> (starts: [UInt64], lengths: [UInt32], lineEnding: LineEnding) {
        var starts: [UInt64] = []
        var lengths: [UInt32] = []
        let capacity = estimatedLineCapacity(for: bodyRange.count)
        starts.reserveCapacity(capacity)
        lengths.reserveCapacity(capacity)
        var detected: LineEnding?

        func appendLine(_ start: Int, _ end: Int) {
            starts.append(UInt64(start))
            lengths.append(UInt32(end - start))
        }

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let buf = raw.bindMemory(to: UInt8.self)
            var lineStart = bodyRange.lowerBound
            var i = bodyRange.lowerBound
            while i < bodyRange.upperBound {
                let byte = buf[i]
                if byte == 0x0D {
                    appendLine(lineStart, i)
                    if i + 1 < bodyRange.upperBound, buf[i + 1] == 0x0A {
                        if detected == nil { detected = .crlf }
                        i += 2
                    } else {
                        if detected == nil { detected = .cr }
                        i += 1
                    }
                    lineStart = i
                } else if byte == 0x0A {
                    appendLine(lineStart, i)
                    if detected == nil { detected = .lf }
                    i += 1
                    lineStart = i
                } else {
                    i += 1
                }
            }
            appendLine(lineStart, bodyRange.upperBound)
        }
        return (starts, lengths, detected ?? .lf)
    }

    private static func indexLinesUTF16(
        _ data: Data,
        bodyRange: Range<Int>,
        littleEndian: Bool
    ) -> (starts: [UInt64], lengths: [UInt32], lineEnding: LineEnding) {
        var starts: [UInt64] = []
        var lengths: [UInt32] = []
        let capacity = estimatedLineCapacity(for: bodyRange.count)
        starts.reserveCapacity(capacity)
        lengths.reserveCapacity(capacity)
        var detected: LineEnding?

        func appendLine(_ start: Int, _ end: Int) {
            starts.append(UInt64(start))
            lengths.append(UInt32(end - start))
        }

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let buf = raw.bindMemory(to: UInt8.self)
            func unit(at offset: Int) -> UInt16 {
                let b0 = UInt16(buf[offset]), b1 = UInt16(buf[offset + 1])
                return littleEndian ? (b1 << 8) | b0 : (b0 << 8) | b1
            }
            let step = 2
            var lineStart = bodyRange.lowerBound
            var i = bodyRange.lowerBound
            while i + step <= bodyRange.upperBound {
                let u = unit(at: i)
                if u == 0x000D {
                    appendLine(lineStart, i)
                    if i + step * 2 <= bodyRange.upperBound, unit(at: i + step) == 0x000A {
                        if detected == nil { detected = .crlf }
                        i += step * 2
                    } else {
                        if detected == nil { detected = .cr }
                        i += step
                    }
                    lineStart = i
                } else if u == 0x000A {
                    appendLine(lineStart, i)
                    if detected == nil { detected = .lf }
                    i += step
                    lineStart = i
                } else {
                    i += step
                }
            }
            appendLine(lineStart, bodyRange.upperBound)
        }
        return (starts, lengths, detected ?? .lf)
    }
}
