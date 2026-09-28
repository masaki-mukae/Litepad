import AppKit
import CoreText

/// Core Textで自前描画するテキストキャンバス。
/// 責務: (1) CTLineベースの行描画（可視範囲のみ）, (2) NSTextInputClientによるIME入力,
/// (3) カーソル移動・通常選択・矩形選択, (4) Undo/Redo登録, (5) 検索・置換の実行。
///
/// 1ファイルへ実装が集中しすぎないよう、責務ごとに`extension`を別ファイルへ分けている。
/// このファイルには「状態そのもの」「選択範囲の正規化」「編集の起点となるUndo登録つきの
/// 基本操作」「レイアウト（フレームサイズ）」だけを置く。他の責務は以下のファイルを参照:
/// - `TextCanvasView+Drawing.swift`: `draw(_:)`とその下請け描画処理
/// - `TextCanvasView+Input.swift`: マウス・キーボードのエントリポイント、カーソル移動計算
/// - `TextCanvasView+Actions.swift`: コピー/カット/ペースト/Undo/Redo/ブックマークの各アクション
/// - `TextCanvasView+FindReplace.swift`: 検索・置換
/// - `TextCanvasView+TextInputClient.swift`: `NSTextInputClient`準拠（IME入力）
final class TextCanvasView: NSView, NSTextInputClient {
    let buffer: DocumentBuffer
    var font: NSFont = AppSettings.shared.font
    var paragraphStyle = NSParagraphStyle.default
    let textInset: CGFloat = 8
    let topInset: CGFloat = 6
    var lineHeight: CGFloat = 0
    var baselineOffset: CGFloat = 0

    /// 巨大ファイルでも開いた瞬間に全行を測定しないよう、これまでに見た最大幅だけを保持する。
    /// 可視行を描画するたびに更新され、単調増加のみ行う（縮むことはない）。
    var maxLineWidth: CGFloat = 400

    var cursor = CursorPosition(line: 0, column: 0)
    var selectionAnchor: CursorPosition?
    /// Option（⌥）ドラッグで開始された場合に矩形（ボックス）選択として扱う。
    var isRectangularSelection = false
    var composingText: String = ""
    var composingLine: Int = -1

    let bookmarkStore = BookmarkStore()
    let gutterPadding: CGFloat = 6

    /// 行番号ガター（有効な場合）を含めた、テキスト本体の描画開始X座標。
    var textStartX: CGFloat {
        (AppSettings.shared.showLineNumbers ? gutterWidth : 0) + textInset
    }

    /// 行番号ガターの幅。最終行の桁数から算出し、最低3桁ぶんは確保する。
    var gutterWidth: CGFloat {
        guard AppSettings.shared.showLineNumbers else { return 0 }
        let digitCount = max(3, String(buffer.lineCount).count)
        let charWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        return CGFloat(digitCount) * charWidth + gutterPadding * 2
    }

    /// Undo登録・未保存インジケータ更新のために弱参照で持つ。
    weak var document: LitepadDocument?

    /// 選択範囲の文字数/バイト数表示（ステータスバー用テキスト）が変わるたびに呼ばれる。
    var onSelectionStatusChanged: ((String) -> Void)?

    /// ウィンドウ下部に表示する、現在の選択範囲についての文字数/バイト数テキスト。
    /// 選択が無い場合は空文字列（サクラエディタの選択情報表示に相当）。
    var selectionStatusText: String {
        SelectionStatusFormatter.text(
            buffer: buffer,
            selection: normalizedSelection,
            rectSelection: normalizedRectSelection.map {
                (topLine: $0.topLine, bottomLine: $0.bottomLine, leftColumn: $0.leftColumn, rightColumn: $0.rightColumn)
            }
        )
    }

    /// ファイル拡張子から判定した言語のシンタックスハイライト定義（対応言語でなければnil）。
    var currentLanguage: LanguageDefinition? {
        guard let ext = buffer.fileURL?.pathExtension, !ext.isEmpty else { return nil }
        return LanguageDefinition.detect(forExtension: ext)
    }

    let syntaxCache = SyntaxHighlightCache()

    private var caretTimer: Timer?
    var isCaretVisible = true

    /// 表示倍率（サクラエディタの「文字表示倍率」相当）。環境設定のフォントサイズ自体は
    /// 変えず、このウィンドウの描画だけを拡大縮小する。⌘+スクロール、またはトラック
    /// パッドのピンチジェスチャーで変更する（`TextCanvasView+Input.swift`参照）。
    /// ウィンドウ単位の一時的な状態で、環境設定には保存しない。
    private(set) var zoomScale: CGFloat = 1.0 {
        didSet {
            applyFontMetrics()
            maxLineWidth = 400
            updateFrameSize()
            needsDisplay = true
            onZoomChanged?(zoomPercentText)
        }
    }
    private let minZoomScale: CGFloat = 0.25
    private let maxZoomScale: CGFloat = 4.0

    /// 表示倍率が変わるたびに呼ばれる（ステータスバー右下の表示更新用）。
    var onZoomChanged: ((String) -> Void)?

    /// ステータスバーに表示する表示倍率のテキスト（例: "100%"）。
    var zoomPercentText: String {
        "\(Int((zoomScale * 100).rounded()))%"
    }

    /// `factor`倍（例: 1.1なら10%拡大）だけ表示倍率を変更する。範囲外にはクランプする。
    func adjustZoom(by factor: CGFloat) {
        let clamped = min(max(zoomScale * factor, minZoomScale), maxZoomScale)
        guard clamped != zoomScale else { return }
        zoomScale = clamped
    }

    init(buffer: DocumentBuffer) {
        self.buffer = buffer
        super.init(frame: .zero)
        applyFontMetrics()
        updateFrameSize()
        startCaretBlink()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: AppSettings.didChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        caretTimer?.invalidate()
        selectionStatusWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    /// フォント・タブ幅から行の高さやタブ間隔を再計算する（初期化時・環境設定変更時・
    /// 表示倍率変更時に呼ぶ）。
    private func applyFontMetrics() {
        font = AppSettings.shared.font(atZoom: zoomScale)
        lineHeight = ceil(font.ascender - font.descender + font.leading) + 6
        baselineOffset = ceil(font.ascender)

        let charWidth = ("M" as NSString).size(withAttributes: [.font: font]).width
        let style = NSMutableParagraphStyle()
        style.tabStops = []
        style.defaultTabInterval = max(charWidth * CGFloat(AppSettings.shared.tabWidth), charWidth)
        paragraphStyle = style
    }

    @objc private func handleSettingsChanged() {
        applyFontMetrics()
        // フォントサイズが変わると幅のキャッシュが無効になるため測り直す。
        maxLineWidth = 400
        updateFrameSize()
        needsDisplay = true
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override var undoManager: UndoManager? {
        document?.undoManager
    }

    // MARK: - Selection

    struct RectSelection {
        let topLine: Int
        let bottomLine: Int
        let leftColumn: Int
        let rightColumn: Int
    }

    /// `selectionAnchor`と`cursor`のうち前方/後方を判定した範囲（通常選択）。矩形選択中や選択なしの場合はnil。
    var normalizedSelection: (start: CursorPosition, end: CursorPosition)? {
        guard !isRectangularSelection, let anchor = selectionAnchor, anchor != cursor else { return nil }
        return anchor < cursor ? (anchor, cursor) : (cursor, anchor)
    }

    /// 矩形選択の正規化された範囲。通常選択中や選択なしの場合はnil。
    var normalizedRectSelection: RectSelection? {
        guard isRectangularSelection, let anchor = selectionAnchor, anchor != cursor else { return nil }
        return RectSelection(
            topLine: min(anchor.line, cursor.line),
            bottomLine: max(anchor.line, cursor.line),
            leftColumn: min(anchor.column, cursor.column),
            rightColumn: max(anchor.column, cursor.column)
        )
    }

    var hasSelection: Bool {
        guard let anchor = selectionAnchor else { return false }
        return anchor != cursor
    }

    func clearSelection() {
        selectionAnchor = nil
        isRectangularSelection = false
    }

    func extendSelection(to newCursor: CursorPosition) {
        if selectionAnchor == nil { selectionAnchor = cursor }
        cursor = newCursor
    }

    // MARK: - Editing primitives (Undo/Redoの起点)

    /// 全ての「範囲を置き換える」編集（挿入・削除・選択の置き換え・検索置換）の基盤。
    /// 置き換え前のテキストを保存しておき、逆操作をUndoManagerに登録する。
    func applyEdit(from start: CursorPosition, to end: CursorPosition, withText newText: String) {
        let oldText = buffer.text(from: start, to: end)
        let newEnd = buffer.replace(from: start, to: end, withText: newText)
        syntaxCache.invalidate(from: start.line)
        bookmarkStore.adjust(editStart: start, oldEnd: end, newEnd: newEnd)

        undoManager?.registerUndo(withTarget: self) { target in
            target.applyEdit(from: start, to: newEnd, withText: oldText)
            target.afterEdit()
        }

        cursor = newEnd
        clearSelection()
        document?.updateChangeCount(.changeDone)
    }

    /// 矩形編集（削除・矩形上書き）のUndo登録。バッファへの変更は呼び出し側で完了済みの前提で、
    /// 変更前後の行スナップショットだけを受け取ってUndo/Redoを登録する。
    func registerRectUndo(topLine: Int, bottomLine: Int, before: [String], after: [String]) {
        syntaxCache.invalidate(from: topLine)
        undoManager?.registerUndo(withTarget: self) { target in
            for (offset, lineIdx) in (topLine...bottomLine).enumerated() {
                target.buffer.replaceLine(lineIdx, with: before[offset])
            }
            target.registerRectUndo(topLine: topLine, bottomLine: bottomLine, before: after, after: before)
            target.cursor = CursorPosition(line: topLine, column: 0)
            target.clearSelection()
            target.afterEdit()
        }
        document?.updateChangeCount(.changeDone)
    }

    func deleteSelectionIfAny() {
        if let rect = normalizedRectSelection {
            let lines = rect.topLine...rect.bottomLine
            let before = lines.map { buffer.line(at: $0) }
            cursor = buffer.deleteRect(topLine: rect.topLine, bottomLine: rect.bottomLine, leftColumn: rect.leftColumn, rightColumn: rect.rightColumn)
            let after = lines.map { buffer.line(at: $0) }
            registerRectUndo(topLine: rect.topLine, bottomLine: rect.bottomLine, before: before, after: after)
            clearSelection()
        } else if let selection = normalizedSelection {
            applyEdit(from: selection.start, to: selection.end, withText: "")
        }
    }

    /// 選択範囲（通常/矩形どちらも）を`text`で置き換える。矩形選択かつ`text`が単一行の場合は
    /// 各行の同じ列位置に同じ文字列を適用する（矩形上書き／矩形貼り付け）。
    func insertReplacingSelection(_ text: String) {
        if let rect = normalizedRectSelection, !text.contains("\n") {
            let lines = rect.topLine...rect.bottomLine
            let before = lines.map { buffer.line(at: $0) }
            buffer.deleteRect(topLine: rect.topLine, bottomLine: rect.bottomLine, leftColumn: rect.leftColumn, rightColumn: rect.rightColumn)
            cursor = buffer.insertRect(text, topLine: rect.topLine, bottomLine: rect.bottomLine, column: rect.leftColumn)
            let after = lines.map { buffer.line(at: $0) }
            registerRectUndo(topLine: rect.topLine, bottomLine: rect.bottomLine, before: before, after: after)
            clearSelection()
        } else {
            let range = normalizedSelection ?? (cursor, cursor)
            applyEdit(from: range.0, to: range.1, withText: text)
        }
    }

    /// 改行時に、直前の行の先頭にある空白（スペース／タブ）をそのまま新しい行に引き継ぐ
    /// （サクラエディタの「オートインデント」相当）。行末が `{`/`(`/`[`（Pythonでは `:` も）で
    /// 終わっている場合は、さらに1段深くする（スマートインデント）。
    func insertNewlineWithAutoIndent() {
        let referenceLine = normalizedSelection?.start.line ?? normalizedRectSelection?.topLine ?? cursor.line
        var indent = leadingWhitespace(ofLine: referenceLine)
        if shouldIncreaseIndent(afterLine: referenceLine) {
            indent += indentUnit(basedOnLine: referenceLine)
        }
        insertReplacingSelection("\n" + indent)
    }

    private func shouldIncreaseIndent(afterLine lineIdx: Int) -> Bool {
        guard let lastChar = buffer.line(at: lineIdx).reversed().first(where: { $0 != " " && $0 != "\t" }) else {
            return false
        }
        if "{([".contains(lastChar) { return true }
        if lastChar == ":", currentLanguage?.colonTriggersIndent == true { return true }
        return false
    }

    /// 既存の字下げがタブ始まりならタブを、それ以外はスペース4つを1段分の単位とする。
    private func indentUnit(basedOnLine lineIdx: Int) -> String {
        buffer.line(at: lineIdx).first == "\t" ? "\t" : "    "
    }

    func leadingWhitespace(ofLine lineIdx: Int) -> String {
        var result = ""
        for ch in buffer.line(at: lineIdx) {
            guard ch == " " || ch == "\t" else { break }
            result.append(ch)
        }
        return result
    }

    // MARK: - Layout

    /// スクロール可能領域（NSClipViewの可視範囲）のサイズ。まだスクロールビューに
    /// 組み込まれていない場合はゼロを返す。
    private var visibleAreaSize: NSSize {
        enclosingScrollView?.contentView.bounds.size ?? .zero
    }

    /// フレームサイズを「コンテンツの実サイズ」と「可視領域のサイズ」の大きい方に合わせる。
    /// こうしておかないと、コンテンツが可視領域より小さい間は自前の`draw(_:)`が塗る範囲より
    /// 外側にNSClipViewの背景色が見えてしまい、色が違う継ぎ目ができてしまう
    /// （NSClipView側にも同じ色を明示指定してみたが、意味的な色の解決がコンテキストで
    /// 微妙に変わるためか一致しなかった。フレーム自体を広げるのが確実）。
    /// 幅は`draw(_:)`内で可視行を測るたびに単調増加させる（巨大ファイルで全行を測るのを避けるため）。
    func updateFrameSize() {
        let contentHeight = CGFloat(buffer.lineCount) * lineHeight + topInset * 2
        let visible = visibleAreaSize
        let height = max(contentHeight, visible.height)
        let width = max(maxLineWidth, visible.width)
        if width != frame.width || height != frame.height {
            setFrameSize(NSSize(width: width, height: height))
        }
    }

    func growFrameWidthIfNeeded(to width: CGFloat) {
        guard width > maxLineWidth else { return }
        maxLineWidth = width
        updateFrameSize()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let clipView = enclosingScrollView?.contentView else { return }
        clipView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVisibleAreaChange),
            name: NSView.frameDidChangeNotification,
            object: clipView
        )
        updateFrameSize()
    }

    @objc private func handleVisibleAreaChange() {
        updateFrameSize()
    }

    // MARK: - Caret blink

    private func startCaretBlink() {
        caretTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            isCaretVisible.toggle()
            setNeedsDisplay(caretRect())
        }
    }

    // MARK: - Post-edit hooks

    private var selectionStatusWorkItem: DispatchWorkItem?

    /// カーソル移動・選択範囲変更のみ（ドキュメント内容は変わらない）の後処理。
    func afterCursorMove() {
        needsDisplay = true
        isCaretVisible = true
        scrollToVisible(caretRect().insetBy(dx: -40, dy: -40))
        scheduleSelectionStatusUpdate()
    }

    /// 選択範囲のステータス文字列（文字数/バイト数）の再計算をデバウンスする。
    /// マウスドラッグ中は`afterCursorMove()`がドラッグイベントのたびに（1秒間に何十回も）
    /// 呼ばれるため、巨大な選択範囲での計算（数百ms〜数秒かかり得る）を都度そのまま
    /// 実行すると、ドラッグ中の操作感が完全に固まってしまう。直近の呼び出しから
    /// 一定時間（0.1秒）操作が無かった場合にのみ、実際に計算して表示を更新する。
    private func scheduleSelectionStatusUpdate() {
        selectionStatusWorkItem?.cancel()
        guard onSelectionStatusChanged != nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onSelectionStatusChanged?(self.selectionStatusText)
        }
        selectionStatusWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    /// ドキュメント内容が変わる編集の後処理（未保存インジケータも更新する）。
    func afterEdit() {
        updateFrameSize()
        afterCursorMove()
    }
}
