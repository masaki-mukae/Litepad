import AppKit

/// 検索・置換用のフローティングパネル。ウィンドウごとに1つ、非アクティブ化パネルとして持つ。
final class FindPanelController: NSWindowController {
    private weak var textView: TextCanvasView?

    private let searchField = NSTextField()
    private let replaceField = NSTextField()
    private let regexCheckbox = NSButton(checkboxWithTitle: "正規表現", target: nil, action: nil)
    private let caseCheckbox = NSButton(checkboxWithTitle: "大文字小文字を区別", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    init(textView: TextCanvasView) {
        self.textView = textView
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 172),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "検索と置換"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        super.init(window: panel)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let searchLabel = NSTextField(labelWithString: "検索:")
        let replaceLabel = NSTextField(labelWithString: "置換:")
        searchField.placeholderString = "検索文字列"
        replaceField.placeholderString = "置換文字列"

        let findPrevButton = NSButton(title: "前を検索", target: self, action: #selector(findPrevious))
        let findNextButton = NSButton(title: "次を検索", target: self, action: #selector(findNext))
        findNextButton.keyEquivalent = "\r"
        let replaceButton = NSButton(title: "置換して次へ", target: self, action: #selector(replaceAndFindNext))
        let replaceAllButton = NSButton(title: "すべて置換", target: self, action: #selector(replaceAll))

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingTail

        let searchRow = NSStackView(views: [searchLabel, searchField])
        searchRow.orientation = .horizontal
        searchLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let replaceRow = NSStackView(views: [replaceLabel, replaceField])
        replaceRow.orientation = .horizontal
        replaceLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let optionsRow = NSStackView(views: [regexCheckbox, caseCheckbox])
        optionsRow.orientation = .horizontal
        optionsRow.spacing = 16

        let buttonsRow = NSStackView(views: [findPrevButton, findNextButton, replaceButton, replaceAllButton])
        buttonsRow.orientation = .horizontal
        buttonsRow.spacing = 8

        let mainStack = NSStackView(views: [searchRow, replaceRow, optionsRow, buttonsRow, statusLabel])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            searchRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -32),
            replaceRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -32),
            statusLabel.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -32),
        ])
    }

    func showPanel() {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchField)
    }

    private var currentOptions: (useRegex: Bool, caseSensitive: Bool) {
        (regexCheckbox.state == .on, caseCheckbox.state == .on)
    }

    @objc private func findNext() { runFind(forward: true) }
    @objc private func findPrevious() { runFind(forward: false) }

    private func runFind(forward: Bool) {
        guard let textView else { return }
        do {
            let result = try textView.performFind(
                query: searchField.stringValue,
                useRegex: currentOptions.useRegex,
                caseSensitive: currentOptions.caseSensitive,
                forward: forward
            )
            updateStatus(result)
        } catch {
            statusLabel.stringValue = "正規表現エラー: \(error.localizedDescription)"
        }
    }

    @objc private func replaceAndFindNext() {
        guard let textView else { return }
        do {
            let result = try textView.performReplaceCurrentAndFindNext(
                query: searchField.stringValue,
                useRegex: currentOptions.useRegex,
                caseSensitive: currentOptions.caseSensitive,
                replacement: replaceField.stringValue
            )
            updateStatus(result)
        } catch {
            statusLabel.stringValue = "正規表現エラー: \(error.localizedDescription)"
        }
    }

    @objc private func replaceAll() {
        guard let textView else { return }
        do {
            let count = try textView.performReplaceAll(
                query: searchField.stringValue,
                useRegex: currentOptions.useRegex,
                caseSensitive: currentOptions.caseSensitive,
                replacement: replaceField.stringValue
            )
            statusLabel.stringValue = count > 0 ? "\(count)件を置換しました" : "見つかりません"
        } catch {
            statusLabel.stringValue = "正規表現エラー: \(error.localizedDescription)"
        }
    }

    private func updateStatus(_ result: TextCanvasView.FindOutcome) {
        if !result.found {
            statusLabel.stringValue = "見つかりません"
        } else if let index = result.index {
            statusLabel.stringValue = "\(index) / \(result.total) 件"
        } else {
            statusLabel.stringValue = "\(result.total) 件"
        }
    }
}
