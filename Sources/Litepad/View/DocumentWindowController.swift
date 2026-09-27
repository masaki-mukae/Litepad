import AppKit

/// 1ウィンドウ分のUI（テキストキャンバス・スクロールビュー・検索パネル）を組み立てる。
/// 保存確認・タイトルの更新・Undo Managerの提供はNSDocumentが自動で行うため、ここでは扱わない。
final class DocumentWindowController: NSWindowController {
    private let textView: TextCanvasView
    private let statusLabel = NSTextField(labelWithString: "")
    private let encodingLabel = NSTextField(labelWithString: "")
    private let zoomLabel = NSTextField(labelWithString: "")
    private weak var litepadDocument: LitepadDocument?
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

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
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
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // ウィンドウ下部のステータスバー。左に選択範囲の文字数/バイト数（サクラエディタの
        // ステータスバー左下相当、選択が無い間は空欄）、右端に表示倍率、その左隣に
        // 現在の文字コードを表示する（バイト数が文字コードによって変わることを
        // 常に見えるようにするため）。
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        encodingLabel.font = .systemFont(ofSize: 13)
        encodingLabel.textColor = .secondaryLabelColor
        encodingLabel.stringValue = document.buffer.encoding.displayName
        encodingLabel.translatesAutoresizingMaskIntoConstraints = false

        zoomLabel.font = .systemFont(ofSize: 13)
        zoomLabel.textColor = .secondaryLabelColor
        zoomLabel.stringValue = textView.zoomPercentText
        zoomLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusBar = NSView()
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(statusLabel)
        statusBar.addSubview(encodingLabel)
        statusBar.addSubview(zoomLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: encodingLabel.leadingAnchor, constant: -8),
            statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            encodingLabel.trailingAnchor.constraint(equalTo: zoomLabel.leadingAnchor, constant: -8),
            encodingLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            zoomLabel.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -8),
            zoomLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),
        ])

        let container = NSView(frame: contentRect)
        container.addSubview(scrollView)
        container.addSubview(statusBar)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        window.contentView = container

        super.init(window: window)
        litepadDocument = document
        textView.document = document
        textView.onSelectionStatusChanged = { [weak self] text in
            self?.statusLabel.stringValue = text
        }
        textView.onZoomChanged = { [weak self] text in
            self?.zoomLabel.stringValue = text
        }
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

    /// 文字コード変換の直後に、依存するUI（右下の文字コード表示・選択範囲のバイト数）を
    /// 再計算する。選択範囲のバイト数はエンコーディングによって変わるため。
    func refreshEncodingDependentUI() {
        guard let litepadDocument else { return }
        encodingLabel.stringValue = litepadDocument.buffer.encoding.displayName
        statusLabel.stringValue = textView.selectionStatusText
    }
}
