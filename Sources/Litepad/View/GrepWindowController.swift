import AppKit

/// フォルダ内複数ファイルを横断検索するGrepウィンドウ（サクラエディタのGrep相当）。
/// 結果一覧をダブルクリックすると該当ファイルを開いてその行にジャンプする。
final class GrepWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = GrepWindowController()

    private let queryField = NSTextField()
    private let folderField = NSTextField()
    private let patternField = NSTextField()
    private let regexCheckbox = NSButton(checkboxWithTitle: "正規表現", target: nil, action: nil)
    private let caseCheckbox = NSButton(checkboxWithTitle: "大文字小文字を区別", target: nil, action: nil)
    private let recursiveCheckbox = NSButton(checkboxWithTitle: "サブフォルダも検索", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()

    private var results: [GrepMatch] = []
    private var selectedFolder: URL?

    private init() {
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Grep（フォルダ内検索）"
        panel.center()
        super.init(window: panel)
        buildUI()
        recursiveCheckbox.state = .on
        patternField.stringValue = "*"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let queryLabel = NSTextField(labelWithString: "検索文字列:")
        let folderLabel = NSTextField(labelWithString: "フォルダ:")
        let patternLabel = NSTextField(labelWithString: "対象ファイル:")
        [queryLabel, folderLabel, patternLabel].forEach { $0.widthAnchor.constraint(equalToConstant: 90).isActive = true }

        folderField.isEditable = false
        folderField.placeholderString = "検索するフォルダを選択してください"
        let chooseFolderButton = NSButton(title: "選択…", target: self, action: #selector(chooseFolder))

        let queryRow = NSStackView(views: [queryLabel, queryField])
        queryRow.orientation = .horizontal

        let folderRow = NSStackView(views: [folderLabel, folderField, chooseFolderButton])
        folderRow.orientation = .horizontal

        let patternRow = NSStackView(views: [patternLabel, patternField])
        patternRow.orientation = .horizontal

        let optionsRow = NSStackView(views: [regexCheckbox, caseCheckbox, recursiveCheckbox])
        optionsRow.orientation = .horizontal
        optionsRow.spacing = 16

        let searchButton = NSButton(title: "検索実行", target: self, action: #selector(runSearch))
        searchButton.keyEquivalent = "\r"
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        let buttonRow = NSStackView(views: [searchButton, statusLabel])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12

        let fileColumn = NSTableColumn(identifier: .init("file"))
        fileColumn.title = "ファイル"
        fileColumn.width = 200
        let lineColumn = NSTableColumn(identifier: .init("line"))
        lineColumn.title = "行"
        lineColumn.width = 44
        let textColumn = NSTableColumn(identifier: .init("text"))
        textColumn.title = "内容"
        textColumn.width = 360

        tableView.addTableColumn(fileColumn)
        tableView.addTableColumn(lineColumn)
        tableView.addTableColumn(textColumn)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.usesAlternatingRowBackgroundColors = true

        let resultsScrollView = NSScrollView()
        resultsScrollView.documentView = tableView
        resultsScrollView.hasVerticalScroller = true
        resultsScrollView.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = NSStackView(views: [queryRow, folderRow, patternRow, optionsRow, buttonRow])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 10
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(mainStack)
        contentView.addSubview(resultsScrollView)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            queryRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            folderRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            patternRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),

            resultsScrollView.topAnchor.constraint(equalTo: mainStack.bottomAnchor, constant: 12),
            resultsScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            resultsScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            resultsScrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.selectedFolder = url
            self.folderField.stringValue = url.path
        }
    }

    @objc private func runSearch() {
        guard let folder = selectedFolder else {
            statusLabel.stringValue = "フォルダを選択してください"
            return
        }
        let query = queryField.stringValue
        guard !query.isEmpty else { return }

        let patterns = GrepEngine.parsePatterns(patternField.stringValue)
        let useRegex = regexCheckbox.state == .on
        let caseSensitive = caseCheckbox.state == .on
        let recursive = recursiveCheckbox.state == .on

        statusLabel.stringValue = "検索中…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let matches = (try? GrepEngine.search(
                folder: folder,
                patterns: patterns,
                recursive: recursive,
                query: query,
                useRegex: useRegex,
                caseSensitive: caseSensitive
            )) ?? []
            DispatchQueue.main.async {
                guard let self else { return }
                self.results = matches
                self.tableView.reloadData()
                self.statusLabel.stringValue = "\(matches.count)件見つかりました"
            }
        }
    }

    @objc private func rowDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < results.count else { return }
        let match = results[row]
        NSDocumentController.shared.openDocument(withContentsOf: match.fileURL, display: true) { document, _, _ in
            guard let document = document as? LitepadDocument else { return }
            let controller = document.windowControllers.compactMap { $0 as? DocumentWindowController }.first
            controller?.revealMatch(line: match.lineNumber - 1, startColumn: match.startColumn, endColumn: match.endColumn)
        }
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < results.count else { return nil }
        let match = results[row]
        let text: String
        switch tableColumn?.identifier.rawValue {
        case "file": text = match.fileURL.lastPathComponent
        case "line": text = String(match.lineNumber)
        default: text = match.lineText.trimmingCharacters(in: .whitespaces)
        }

        let identifier = NSUserInterfaceItemIdentifier("GrepCell")
        let field: NSTextField
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            field = reused
        } else {
            field = NSTextField(labelWithString: "")
            field.identifier = identifier
            field.lineBreakMode = .byTruncatingTail
        }
        field.stringValue = text
        return field
    }
}
