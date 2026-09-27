import AppKit

/// フォント・タブ幅の環境設定ウィンドウ。macOS標準のフォントパネルを使ってフォントを選ぶ。
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    static let shared = PreferencesWindowController()

    private let fontLabel = NSTextField(labelWithString: "")
    private let tabWidthField = NSTextField()
    private let showLineNumbersCheckbox = NSButton(checkboxWithTitle: "行番号を表示", target: nil, action: nil)

    private init() {
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 190),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "環境設定"
        panel.center()
        super.init(window: panel)
        window?.delegate = self
        buildUI()
        refreshFontLabel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let fontRowLabel = NSTextField(labelWithString: "フォント:")
        fontLabel.lineBreakMode = .byTruncatingTail
        let changeFontButton = NSButton(title: "変更…", target: self, action: #selector(showFontPanel))
        let fontRow = NSStackView(views: [fontRowLabel, fontLabel, changeFontButton])
        fontRow.orientation = .horizontal
        fontRow.spacing = 8
        fontRowLabel.widthAnchor.constraint(equalToConstant: 70).isActive = true

        let tabRowLabel = NSTextField(labelWithString: "タブ幅:")
        tabWidthField.stringValue = String(AppSettings.shared.tabWidth)
        tabWidthField.target = self
        tabWidthField.action = #selector(tabWidthChanged)
        tabWidthField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        let stepper = NSStepper()
        stepper.minValue = 1
        stepper.maxValue = 16
        stepper.integerValue = AppSettings.shared.tabWidth
        stepper.target = self
        stepper.action = #selector(tabWidthStepperChanged)
        let tabRow = NSStackView(views: [tabRowLabel, tabWidthField, stepper])
        tabRow.orientation = .horizontal
        tabRow.spacing = 8
        tabRowLabel.widthAnchor.constraint(equalToConstant: 70).isActive = true
        self.stepper = stepper

        showLineNumbersCheckbox.state = AppSettings.shared.showLineNumbers ? .on : .off
        showLineNumbersCheckbox.target = self
        showLineNumbersCheckbox.action = #selector(showLineNumbersChanged)

        let resetButton = NSButton(title: "デフォルトに戻す", target: self, action: #selector(resetToDefaults))

        let mainStack = NSStackView(views: [fontRow, tabRow, showLineNumbersCheckbox, resetButton])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 16
        mainStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor),
        ])
    }

    private var stepper: NSStepper?

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshFontLabel() {
        let font = AppSettings.shared.font
        fontLabel.stringValue = "\(font.displayName ?? font.fontName) \(Int(AppSettings.shared.fontSize))pt"
    }

    @objc private func showFontPanel() {
        let fontManager = NSFontManager.shared
        fontManager.target = self
        fontManager.setSelectedFont(AppSettings.shared.font, isMultiple: false)
        window?.makeFirstResponder(self)
        fontManager.orderFrontFontPanel(self)
    }

    /// NSFontPanelでフォントが選択されたときにレスポンダーチェーン経由で呼ばれる。
    @objc func changeFont(_ sender: Any?) {
        guard let fontManager = sender as? NSFontManager else { return }
        let newFont = fontManager.convert(AppSettings.shared.font)
        AppSettings.shared.fontName = newFont.fontName
        AppSettings.shared.fontSize = Double(newFont.pointSize)
        refreshFontLabel()
    }

    @objc private func tabWidthChanged() {
        let value = max(1, min(16, tabWidthField.integerValue))
        tabWidthField.integerValue = value
        stepper?.integerValue = value
        AppSettings.shared.tabWidth = value
    }

    @objc private func tabWidthStepperChanged() {
        guard let stepper else { return }
        tabWidthField.integerValue = stepper.integerValue
        AppSettings.shared.tabWidth = stepper.integerValue
    }

    @objc private func showLineNumbersChanged() {
        AppSettings.shared.showLineNumbers = showLineNumbersCheckbox.state == .on
    }

    @objc private func resetToDefaults() {
        AppSettings.shared.resetToDefaults()
        tabWidthField.stringValue = String(AppSettings.shared.tabWidth)
        stepper?.integerValue = AppSettings.shared.tabWidth
        showLineNumbersCheckbox.state = AppSettings.shared.showLineNumbers ? .on : .off
        refreshFontLabel()
    }
}
