import Foundation

/// 行の位置情報（1行12バイト）。ブロック内のローカル配列としてのみ存在する。
private struct LinePosition {
    var start: UInt64
    var length: UInt32
}

/// 固定サイズ程度に保たれる行のかたまり。行データを1本の巨大な配列ではなく多数の
/// ブロックに分割して持つことで、挿入・削除のコストをブロックサイズ程度（およびブロック数
/// ぶんの線形探索）に抑える。1本の配列のままだと、行数が数千万に達する巨大ファイルの
/// 先頭付近で改行を1つ挿入・削除するたびに、行数に比例した配列全体のmemmove
/// （数百MB規模）が発生してしまう。
private final class LineBlock {
    var positions: [LinePosition] = []
    /// ブロック内ローカルインデックス → 実体化済みテキスト。編集された行のみ持つ。
    var materialized: [Int: String] = [:]

    var count: Int { positions.count }
}

/// 行ごとに「未編集＝ファイル上のバイト範囲を指すだけ」「編集済み＝実体化したString」を
/// 使い分ける行ストレージ。`DocumentBuffer`の内部実装であり、巨大ファイルでもmmapされた
/// ページの分だけが実メモリに乗る（未編集行はStringを一切生成しない）ことで、
/// 開いた瞬間の読み込み時間とメモリ使用量をファイルサイズに対してほぼ線形に保つ。
///
/// 行データは`targetBlockSize`程度のブロックに分割して保持する（`LineBlock`参照）。
/// 挿入・削除は該当ブロック内だけで完結し（ブロックが大きくなり過ぎたら分割、
/// 小さくなり過ぎたら隣と併合）、ブロックの探索には直近アクセス位置のヒントを使うため、
/// 逐次アクセス（検索・保存・構文ハイライトなど、行を0から順に読むケースやカーソル移動）は
/// 実質O(1)、行数に依存しない。本家サクラエディタが行の連結リスト＋直近参照キャッシュ
/// （`m_pCodePrevRefer`）で同じ問題を解いているのと同じ発想を、配列ベースで実現している。
final class LineStore {
    private var data: Data
    private(set) var encoding: TextEncodingKind
    private(set) var detectedLineEnding: LineEnding

    private var blocks: [LineBlock]
    private var totalCount: Int = 0

    /// 直近にlocateで見つかったブロックの位置。次回のlocateはここから探索を始める。
    private var hintBlockIndex: Int = 0
    private var hintBlockGlobalStart: Int = 0

    private static let sentinelLength = UInt32.max
    private static let targetBlockSize = 4096
    private static let maxBlockSize = 8192
    private static let minBlockSize = 1024

    init(encoding: TextEncodingKind = .utf8) {
        data = Data()
        self.encoding = encoding
        detectedLineEnding = .lf
        let block = LineBlock()
        block.positions = [LinePosition(start: 0, length: 0)]
        blocks = [block]
        totalCount = 1
    }

    init(text: String, encoding: TextEncodingKind) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.isEmpty ? [""] : normalized.components(separatedBy: "\n")
        data = Data()
        self.encoding = encoding
        detectedLineEnding = .lf
        blocks = []
        var index = 0
        while index < lines.count {
            let end = min(index + Self.targetBlockSize, lines.count)
            let block = LineBlock()
            block.positions.reserveCapacity(end - index)
            for i in index..<end {
                block.positions.append(LinePosition(start: 0, length: Self.sentinelLength))
                block.materialized[i - index] = lines[i]
            }
            blocks.append(block)
            index = end
        }
        totalCount = lines.count
    }

    init(contentsOf url: URL) throws {
        let mapped = try Data(contentsOf: url, options: [.mappedIfSafe])
        let (detectedEncoding, bodyRange) = TextFileCodec.detectEncoding(mapped)
        data = mapped
        encoding = detectedEncoding
        let indexed = LineIndexScanner.indexLines(in: mapped, bodyRange: bodyRange, encoding: detectedEncoding)
        detectedLineEnding = indexed.lineEnding

        let n = indexed.starts.count
        blocks = []
        blocks.reserveCapacity(n / Self.targetBlockSize + 1)
        var index = 0
        while index < n {
            let end = min(index + Self.targetBlockSize, n)
            let block = LineBlock()
            block.positions.reserveCapacity(end - index)
            for i in index..<end {
                block.positions.append(LinePosition(start: indexed.starts[i], length: indexed.lengths[i]))
            }
            blocks.append(block)
            index = end
        }
        totalCount = n
    }

    var count: Int { totalCount }

    /// 文字コードを変換する。テキストの内容そのものは変わらず、以後の保存で使うバイト列
    /// 表現だけが変わる。未実体化行（元ファイルのバイト範囲を指しているだけの行）は、
    /// 切り替える前に「現在の」エンコーディングで一度デコードして実体化させてから
    /// エンコーディングを差し替える（先に切り替えてしまうと、元のバイト列を新しい
    /// エンコーディングとして誤って解釈してしまい、文字化けする）。
    /// 巨大ファイルでは全行がメモリ上のStringになる（mmapの遅延デコードの恩恵を失う）が、
    /// 文字コード変換自体がファイル全体のバイト列を書き換える操作である以上、避けられない。
    func reassignEncoding(_ newEncoding: TextEncodingKind) {
        guard newEncoding != encoding else { return }
        for block in blocks {
            for li in 0..<block.count where block.materialized[li] == nil {
                block.materialized[li] = TextFileCodec.decodeLine(originalBytes(block.positions[li]), encoding: encoding)
            }
        }
        encoding = newEncoding
    }

    func line(at index: Int) -> String {
        guard index >= 0, index < totalCount else { return "" }
        let (bi, li) = locate(index)
        let block = blocks[bi]
        if let cached = block.materialized[li] { return cached }
        let decoded = TextFileCodec.decodeLine(originalBytes(block.positions[li]), encoding: encoding)
        block.materialized[li] = decoded
        return decoded
    }

    func setLine(_ index: Int, to text: String) {
        guard index >= 0, index < totalCount else { return }
        let (bi, li) = locate(index)
        blocks[bi].materialized[li] = text
    }

    func insertLine(_ text: String, at index: Int) {
        guard index >= 0, index <= totalCount else { return }
        let (bi, li) = locate(index)
        let block = blocks[bi]
        shiftMaterializedKeys(in: block, from: li, by: 1)
        block.positions.insert(LinePosition(start: 0, length: Self.sentinelLength), at: li)
        block.materialized[li] = text
        totalCount += 1
        invalidateHint()
        splitIfNeeded(blockIndex: bi)
    }

    func removeLine(at index: Int) {
        guard index >= 0, index < totalCount else { return }
        let (bi, li) = locate(index)
        let block = blocks[bi]
        block.materialized.removeValue(forKey: li)
        shiftMaterializedKeys(in: block, from: li + 1, by: -1)
        block.positions.remove(at: li)
        totalCount -= 1
        invalidateHint()
        mergeIfNeeded(blockIndex: bi)
    }

    /// `range`が単一ブロックに収まっていればそのブロック内だけで、複数ブロックに
    /// またがっていれば「開始ブロックの末尾側を削る」「完全に含まれる中間ブロックを
    /// 丸ごと落とす」「終了ブロックの先頭側を削る」の3段階で行う。1行ずつ削除する
    /// ループにはしない（範囲が大きい場合にブロック探索コストが積み重なるため）。
    func removeLines(_ range: Range<Int>) {
        guard !range.isEmpty else { return }
        let (startBlock, startLocal) = locate(range.lowerBound)
        let (endBlockInclusive, endLocalExclusive) = locate(range.upperBound)

        if startBlock == endBlockInclusive {
            let block = blocks[startBlock]
            let removeCount = endLocalExclusive - startLocal
            for i in startLocal..<endLocalExclusive { block.materialized.removeValue(forKey: i) }
            shiftMaterializedKeys(in: block, from: endLocalExclusive, by: -removeCount)
            block.positions.removeSubrange(startLocal..<endLocalExclusive)
            totalCount -= removeCount
            invalidateHint()
            mergeIfNeeded(blockIndex: startBlock)
            return
        }

        let startBlockRef = blocks[startBlock]
        let startRemoveCount = startBlockRef.count - startLocal
        for i in startLocal..<startBlockRef.count { startBlockRef.materialized.removeValue(forKey: i) }
        startBlockRef.positions.removeSubrange(startLocal..<startBlockRef.count)
        totalCount -= startRemoveCount

        if endBlockInclusive - 1 >= startBlock + 1 {
            var removedMiddleCount = 0
            for bi in (startBlock + 1)..<endBlockInclusive { removedMiddleCount += blocks[bi].count }
            blocks.removeSubrange((startBlock + 1)..<endBlockInclusive)
            totalCount -= removedMiddleCount
        }

        let endBlockIndexAfterRemoval = startBlock + 1
        if endBlockIndexAfterRemoval < blocks.count {
            let endBlockRef = blocks[endBlockIndexAfterRemoval]
            for i in 0..<endLocalExclusive { endBlockRef.materialized.removeValue(forKey: i) }
            shiftMaterializedKeys(in: endBlockRef, from: endLocalExclusive, by: -endLocalExclusive)
            endBlockRef.positions.removeSubrange(0..<endLocalExclusive)
            totalCount -= endLocalExclusive
        }

        invalidateHint()
        mergeIfNeeded(blockIndex: startBlock)
    }

    /// 全行を`handle`へ書き出す。1行ずつ`Data`を作ってコピーするのではなく、
    /// 未編集行が元ファイル上で物理的に連続している区間（＝挿入・削除が挟まっていない範囲。
    /// ブロック境界をまたいでもよい）をまとめて検出し、区間ごとにmmap上のバイト列を直接
    /// （コピー用の中間`Data`を作らずポインタ経由で）書き出す。編集が一切ない巨大ファイルでは、
    /// この区間がファイル全体そのものになるため、保存はほぼ「ファイルの生コピー」と同じ
    /// 速さになる。編集された行だけが文字列としてエンコードされ、小さくまとめて書き出される。
    func write(to handle: FileHandle, lineEnding: LineEnding) throws {
        let separator = TextFileCodec.encodeLineContent(lineEnding.rawValue, as: encoding)
        let terminatorLength = Int(separator.count)
        let chunkThreshold = 1 << 20

        var chunk = Data()
        chunk.reserveCapacity(chunkThreshold)
        chunk.append(TextFileCodec.bomPrefix(for: encoding))

        func flushChunk() throws {
            guard !chunk.isEmpty else { return }
            try handle.write(contentsOf: chunk)
            chunk.removeAll(keepingCapacity: true)
        }

        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var isFirst = true
            var runStart: Int?
            var runEnd = 0

            func flushRun() throws {
                guard let start = runStart else { return }
                try flushChunk()
                var offset = start
                while offset < runEnd {
                    let pieceLength = min(chunkThreshold, runEnd - offset)
                    let piece = Data(
                        bytesNoCopy: UnsafeMutableRawPointer(mutating: base + offset),
                        count: pieceLength,
                        deallocator: .none
                    )
                    try handle.write(contentsOf: piece)
                    offset += pieceLength
                }
                runStart = nil
            }

            for block in blocks {
                for li in 0..<block.count {
                    if let text = block.materialized[li] {
                        try flushRun()
                        if !isFirst { chunk.append(separator) }
                        isFirst = false
                        chunk.append(TextFileCodec.encodeLineContent(text, as: encoding))
                        if chunk.count >= chunkThreshold { try flushChunk() }
                        continue
                    }

                    let pos = block.positions[li]
                    guard pos.length != Self.sentinelLength else {
                        // 実体化されていないのにsentinelなのは不変条件違反のはずだが、
                        // 直接ポインタ演算を行うため防御的に空行として扱う。
                        try flushRun()
                        if !isFirst { chunk.append(separator) }
                        isFirst = false
                        continue
                    }
                    let start = Int(pos.start)
                    let end = start + Int(pos.length)
                    if let _ = runStart, start == runEnd + terminatorLength {
                        runEnd = end
                    } else {
                        try flushRun()
                        if !isFirst { chunk.append(separator) }
                        isFirst = false
                        runStart = start
                        runEnd = end
                    }
                }
            }
            try flushRun()
        }
        try flushChunk()
    }

    // MARK: - ブロック探索

    /// グローバルな行インデックスから、それを含むブロックとブロック内ローカルインデックスを
    /// 求める。`hintBlockIndex`から前後どちらかへ探索するため、逐次アクセスや局所的な
    /// アクセスでは毎回ブロック0から探すより大幅に速い。
    private func locate(_ globalIndex: Int) -> (blockIndex: Int, localIndex: Int) {
        if hintBlockIndex >= blocks.count { hintBlockIndex = blocks.count - 1 }
        var bi = hintBlockIndex
        var blockStart = hintBlockGlobalStart

        if globalIndex >= blockStart {
            while bi < blocks.count {
                let c = blocks[bi].count
                if globalIndex < blockStart + c {
                    hintBlockIndex = bi
                    hintBlockGlobalStart = blockStart
                    return (bi, globalIndex - blockStart)
                }
                blockStart += c
                bi += 1
            }
            let lastIndex = blocks.count - 1
            hintBlockIndex = lastIndex
            hintBlockGlobalStart = blockStart - blocks[lastIndex].count
            return (lastIndex, blocks[lastIndex].count)
        } else {
            while bi > 0 {
                bi -= 1
                blockStart -= blocks[bi].count
                if globalIndex >= blockStart {
                    hintBlockIndex = bi
                    hintBlockGlobalStart = blockStart
                    return (bi, globalIndex - blockStart)
                }
            }
            hintBlockIndex = 0
            hintBlockGlobalStart = 0
            return (0, globalIndex)
        }
    }

    /// ブロック構成（分割・併合・複数ブロックにまたがる削除）が変わった直後は
    /// ヒントが指す位置の意味が変わってしまっているため、次回は素直に再探索させる。
    private func invalidateHint() {
        hintBlockIndex = min(hintBlockIndex, blocks.count - 1)
        hintBlockGlobalStart = 0
        for i in 0..<hintBlockIndex { hintBlockGlobalStart += blocks[i].count }
    }

    private func originalBytes(_ position: LinePosition) -> Data {
        guard position.length != Self.sentinelLength else { return Data() }
        let start = Int(position.start)
        return data.subdata(in: start..<(start + Int(position.length)))
    }

    /// 行の挿入・削除に伴い、ブロック内ローカルインデックス`localIndex`以降にある
    /// 実体化済み行のキーを`delta`だけずらす。ブロックサイズは高々`maxBlockSize`程度に
    /// 抑えられているため、この再構築は常に軽い。
    private func shiftMaterializedKeys(in block: LineBlock, from localIndex: Int, by delta: Int) {
        guard !block.materialized.isEmpty else { return }
        let toShift = block.materialized.filter { $0.key >= localIndex }
        guard !toShift.isEmpty else { return }
        for key in toShift.keys { block.materialized.removeValue(forKey: key) }
        for (key, value) in toShift { block.materialized[key + delta] = value }
    }

    private func splitIfNeeded(blockIndex: Int) {
        let block = blocks[blockIndex]
        guard block.count > Self.maxBlockSize else { return }
        let mid = block.count / 2
        let newBlock = LineBlock()
        newBlock.positions = Array(block.positions[mid...])
        block.positions.removeSubrange(mid...)
        var moved: [Int: String] = [:]
        for (key, value) in block.materialized where key >= mid {
            moved[key - mid] = value
        }
        if !moved.isEmpty {
            block.materialized = block.materialized.filter { $0.key < mid }
        }
        newBlock.materialized = moved
        blocks.insert(newBlock, at: blockIndex + 1)
    }

    private func mergeIfNeeded(blockIndex: Int) {
        guard blocks.count > 1, blockIndex >= 0, blockIndex < blocks.count else { return }
        let block = blocks[blockIndex]
        guard block.count < Self.minBlockSize else { return }

        if blockIndex + 1 < blocks.count, block.count + blocks[blockIndex + 1].count <= Self.maxBlockSize {
            mergeBlocks(into: blockIndex, from: blockIndex + 1)
            return
        }
        if blockIndex - 1 >= 0, blocks[blockIndex - 1].count + block.count <= Self.maxBlockSize {
            mergeBlocks(into: blockIndex - 1, from: blockIndex)
        }
    }

    private func mergeBlocks(into targetIndex: Int, from sourceIndex: Int) {
        let target = blocks[targetIndex]
        let source = blocks[sourceIndex]
        let offset = target.count
        target.positions.append(contentsOf: source.positions)
        for (key, value) in source.materialized {
            target.materialized[offset + key] = value
        }
        blocks.remove(at: sourceIndex)
    }
}
