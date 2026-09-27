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

    override class var autosavesInPlace: Bool { false }

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
        try buffer.write(to: url)
        // 実ファイルへの保存に成功したので、クラッシュ復元用のバックアップはもう不要。
        AutoSaveManager.removeBackup(for: autosaveID)
    }

    override func close() {
        autosaveTimer?.invalidate()
        // close()に到達する時点で「保存する/しない」の確認は既に済んでいるため、
        // どちらの結果であれバックアップは役目を終えている。
        AutoSaveManager.removeBackup(for: autosaveID)
        super.close()
    }

    /// クラッシュ・強制終了からの復元用: バックアップファイルから読み込んだ内容をそのまま
    /// 引き継ぎ、未保存の変更として扱う。`buffer`自体はバックアップファイルを読み込んだ結果
    /// なので、拡張子に基づく構文ハイライト判定だけ元のファイルパスに合わせ直す。
    func adoptRecoveredContent(_ recoveredBuffer: DocumentBuffer, originalPath: String?) {
        buffer = recoveredBuffer
        let url = originalPath.map { URL(fileURLWithPath: $0) }
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
        AutoSaveManager.writeMeta(for: autosaveID, originalPath: fileURL?.path)
    }
}
