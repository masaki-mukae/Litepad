import AppKit

/// 現在アクティブなドキュメントの型・関数一覧を表示するアウトラインパネル
/// （サクラエディタのアウトライン解析相当）。ダブルクリックで該当行へジャンプする。
final class OutlineWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = OutlineWindowController()

    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var items: [OutlineItem] = []
    /// 対象ドキュメント。`show(for:)`が呼ばれた時点（まだアウトラインウィンドウ自身が
    /// キーウィンドウになる前）で捕まえておく。ウィンドウを前面に出した後で
    /// `NSDocumentController.shared.currentDocument`を参照すると、アウトラインウィンドウ
    /// 自身がキーウィンドウになってしまっているため正しいドキュメントを取得できない。
    private weak var targetDocument: LitepadDocument?

    private init() {
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "アウトライン"
        panel.center()
        super.init(window: panel)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let refreshButton = NSButton(title: "更新", target: self, action: #selector(refresh))
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        let topRow = NSStackView(views: [refreshButton, statusLabel])
        topRow.orientation = .horizontal
        topRow.spacing = 12

        let column = NSTableColumn(identifier: .init("item"))
        column.title = "型・関数"
        column.width = 300
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.usesAlternatingRowBackgroundColors = true

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = NSStackView(views: [topRow, scrollView])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 8
        mainStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scrollView.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])
    }

    /// `document`が`nil`の場合は、直前に対象にしていたドキュメントのまま更新する
    /// （すでにウィンドウが開いている状態で「更新」ボタンから呼ばれるケース）。
    func show(for document: LitepadDocument? = nil) {
        if let document {
            targetDocument = document
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    @objc private func refresh() {
        guard let document = targetDocument,
              let ext = document.fileURL?.pathExtension, !ext.isEmpty else {
            items = []
            statusLabel.stringValue = "対応する言語のファイルではありません"
            tableView.reloadData()
            return
        }
        items = OutlineExtractor.extract(from: document.buffer, fileExtension: ext)
        statusLabel.stringValue = items.isEmpty ? "項目が見つかりませんでした" : "\(items.count)件"
        tableView.reloadData()
    }

    @objc private func rowDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        let item = items[row]
        guard let document = targetDocument else { return }
        let controller = document.windowControllers.compactMap { $0 as? DocumentWindowController }.first
        controller?.revealMatch(line: item.line, startColumn: 0, endColumn: 0)
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < items.count else { return nil }
        let item = items[row]

        let identifier = NSUserInterfaceItemIdentifier("OutlineCell")
        let field: NSTextField
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            field = reused
        } else {
            field = NSTextField(labelWithString: "")
            field.identifier = identifier
            field.lineBreakMode = .byTruncatingTail
        }
        let indentSpaces = String(repeating: "　", count: min(item.indent / 4, 6))
        field.stringValue = "\(indentSpaces)\(item.title)  —  \(item.line + 1)行目"
        return field
    }
}
