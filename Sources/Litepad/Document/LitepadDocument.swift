import AppKit

/// 1ファイル=1ドキュメント。ウィンドウ管理・保存確認・Undo Managerの提供はNSDocumentの
/// 標準機構に任せ、このクラスはバッファの読み書きとウィンドウ生成だけを担当する。
final class LitepadDocument: NSDocument {
    private(set) var buffer = DocumentBuffer(text: "")

    /// このドキュメントを一意に識別するID。自動保存バックアップのファイル名に使う
    /// （保存先パスではなくドキュメントのライフタイムに紐づける必要があるため、
    /// Untitledのまま一度も保存していないドキュメントもバックアップ対象にできる）。
    private let autosaveID = UUID()
    private var autosaveTimer: Timer?
    private static let autosaveInterval: TimeInterval = 60

    /// 保存パネルの文字コードポップアップで選択中の値。パネルが表示されたとき
    /// （初回保存・名前を付けて保存）にのみ設定され、実際に保存が実行された時点で
    /// 適用してクリアする。通常の上書き保存（パネルを出さない）では`nil`のままなので、
    /// 現在のエンコーディングがそのまま使われる。
    private var pendingSaveEncoding: TextEncodingKind?

    /// クラッシュ復元でbookmarkからアクセス権を取り戻した元ファイルのURL。
    /// `startAccessingSecurityScopedResource()`と対で、クローズ時に解放する。
    private var securityScopedURL: URL?

    override class var autosavesInPlace: Bool { false }

    /// Info.plistにCFBundleDocumentTypesを登録していないため、既定の`writableTypes()`は
    /// 空配列になる。これを放置すると、通常の上書き保存（⌘S）でも「現在のfileTypeが
    /// 書き込み可能な形式に含まれない」と判定され、常に名前を付けて保存（Save As）の
    /// パネルへ回されてしまう（既存ファイルを開いて⌘Sで保存されない原因だったバグ）。
    override class var writableTypes: [String] {
        [AppDocumentController.documentTypeName]
    }

    override class func isNativeType(_ type: String) -> Bool {
        type == AppDocumentController.documentTypeName
    }

    override init() {
        super.init()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: Self.autosaveInterval, repeats: true) { [weak self] _ in
            self?.performAutosave()
        }
    }

    override func makeWindowControllers() {
        let controller = DocumentWindowController(document: self)
        addWindowController(controller)
    }

    override func read(from url: URL, ofType typeName: String) throws {
        buffer = try DocumentBuffer(contentsOf: url)
    }

    override func write(to url: URL, ofType typeName: String) throws {
        if let pendingSaveEncoding {
            buffer.reassignEncoding(pendingSaveEncoding)
            self.pendingSaveEncoding = nil
            for controller in windowControllers {
                (controller as? DocumentWindowController)?.refreshEncodingDependentUI()
            }
        }
        try buffer.write(to: url)
        // 実ファイルへの保存に成功したので、クラッシュ復元用のバックアップはもう不要。
        AutoSaveManager.removeBackup(for: autosaveID)
    }

    /// 保存パネル（初回保存・名前を付けて保存）に文字コードの選択欄を追加する
    /// （サクラエディタの「名前を付けて保存」ダイアログの文字コード選択に相当）。
    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        pendingSaveEncoding = buffer.encoding

        let label = NSTextField(labelWithString: "文字コード:")
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        for kind in TextEncodingKind.allCases {
            popUp.addItem(withTitle: kind.displayName)
            popUp.lastItem?.representedObject = kind
        }
        if let index = TextEncodingKind.allCases.firstIndex(of: buffer.encoding) {
            popUp.selectItem(at: index)
        }
        popUp.target = self
        popUp.action = #selector(saveEncodingPopUpChanged(_:))

        let stack = NSStackView(views: [label, popUp])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        accessory.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: accessory.leadingAnchor, constant: 16),
            stack.centerYAnchor.constraint(equalTo: accessory.centerYAnchor),
        ])
        savePanel.accessoryView = accessory
        return true
    }

    @objc private func saveEncodingPopUpChanged(_ sender: NSPopUpButton) {
        pendingSaveEncoding = sender.selectedItem?.representedObject as? TextEncodingKind
    }

    /// 文字コードを変換する（内容は変わらず、次回保存時のバイト列表現だけが変わる）。
    /// 選択範囲のバイト数表示はエンコーディングに依存するため、変換直後に
    /// ステータスバーへ反映されるよう開いている全ウィンドウへ再計算を促す。
    func convertEncoding(to newEncoding: TextEncodingKind) {
        guard buffer.encoding != newEncoding else { return }
        buffer.reassignEncoding(newEncoding)
        updateChangeCount(.changeDone)
        for controller in windowControllers {
            (controller as? DocumentWindowController)?.refreshEncodingDependentUI()
        }
    }

    override func close() {
        autosaveTimer?.invalidate()
        // close()に到達する時点で「保存する/しない」の確認は既に済んでいるため、
        // どちらの結果であれバックアップは役目を終えている。
        AutoSaveManager.removeBackup(for: autosaveID)
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
        super.close()
    }

    /// クラッシュ・強制終了からの復元用: バックアップファイルから読み込んだ内容をそのまま
    /// 引き継ぎ、未保存の変更として扱う。`buffer`自体はバックアップファイルを読み込んだ結果
    /// なので、拡張子に基づく構文ハイライト判定だけ元のファイルパスに合わせ直す。
    ///
    /// App Sandbox環境では、前回起動時のパス文字列だけでは書き込み権限が無いため、
    /// `meta`のsecurity-scoped bookmarkを解決してアクセス権を取り戻す。bookmarkが無い/
    /// 解決できない場合（サンドボックス非対応ビルド、ファイル移動・削除など）は、
    /// 従来通りパス文字列からURLを組み立てるだけに留める（次回保存はSave Asになる）。
    func adoptRecoveredContent(_ recoveredBuffer: DocumentBuffer, meta: AutoSaveManager.Meta?) {
        buffer = recoveredBuffer

        var resolvedURL: URL?
        if let bookmarkData = meta?.bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), url.startAccessingSecurityScopedResource() {
                securityScopedURL = url
                resolvedURL = url
            }
        }
        let url = resolvedURL ?? meta.map { URL(fileURLWithPath: $0.originalPath) }

        buffer.reassignFileURL(url)
        fileURL = url
        updateChangeCount(.changeDone)
    }

    /// 未保存の変更があるときだけ、バックアップ置き場へスナップショットを書き出す。
    /// `buffer.write(to:)`ではなく`writeSnapshot(to:)`を使うのは、前者が`fileURL`を
    /// バックアップのパスに書き換えてしまい、構文ハイライトの言語判定が壊れるため。
    private func performAutosave() {
        guard isDocumentEdited else { return }
        let backupURL = AutoSaveManager.backupURL(for: autosaveID)
        try? buffer.writeSnapshot(to: backupURL)
        AutoSaveManager.writeMeta(for: autosaveID, originalURL: fileURL)
    }
}
