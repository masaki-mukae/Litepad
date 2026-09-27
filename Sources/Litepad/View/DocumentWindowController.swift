import AppKit

/// 1ウィンドウ分のUI（テキストキャンバス・スクロールビュー・検索パネル）を組み立てる。
/// 保存確認・タイトルの更新・Undo Managerの提供はNSDocumentが自動で行うため、ここでは扱わない。
final class DocumentWindowController: NSWindowController {
    private let textView: TextCanvasView
    private var findPanelController: FindPanelController?

    init(document: LitepadDocument) {
        let contentRect = NSRect(x: 0, y: 0, width: 920, height: 640)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        // 全ドキュメントウィンドウを同じタブグループに属させ、システム全体の「タブを優先」設定に
        // 関わらず常にタブとしてまとまるようにする（Finder/Safari/Xcodeと同じ、OS標準のタブ体験）。
        window.tabbingIdentifier = "com.litepad.document"
        window.tabbingMode = .preferred

        let textView = TextCanvasView(buffer: document.buffer)
        self.textView = textView

        let scrollView = NSScrollView(frame: contentRect)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.documentView = textView
        scrollView.drawsBackground = true
        // TextCanvasViewの実際の描画領域はテキスト内容の分だけしかないため、それより広い
        // スクロールビューの余白がデフォルト背景色（textBackgroundColorと別の色）で見えてしまい、
        // 「入力中の行がある領域」と「それ以外の余白」で色が違って見える原因になっていた。
        // NSScrollView自身だけでなく、実際に余白を描画しているNSClipView（contentView）側にも
        // 同じ背景色を明示的に設定しないと継ぎ目が消えない。
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = .textBackgroundColor
        window.contentView = scrollView

        super.init(window: window)
        textView.document = document
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.makeFirstResponder(textView)
    }

    func showFindPanel() {
        if findPanelController == nil {
            findPanelController = FindPanelController(textView: textView)
        }
        findPanelController?.showPanel()
    }

    /// Grep結果のダブルクリックなどから、既知の位置にジャンプする。
    func revealMatch(line: Int, startColumn: Int, endColumn: Int) {
        showWindow(nil)
        textView.revealMatch(line: line, startColumn: startColumn, endColumn: endColumn)
    }
}
