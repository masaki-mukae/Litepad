import Foundation

/// 定期的な自動保存（クラッシュ・強制終了からの復元用バックアップ）を管理する。
/// サクラエディタの自動保存／バックアップ機能に相当する。実際のファイルへは保存せず、
/// アプリ専用のバックアップ置き場にドキュメントごとのスナップショットを書き出しておき、
/// 次回起動時に残っていれば「前回異常終了した」とみなして復元を提案する。
enum AutoSaveManager {
    private static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Litepad/AutoSave", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func backupURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".bak")
    }

    private static func metaURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".meta")
    }

    /// バックアップと一緒に書き出す、元ファイルの情報。
    /// App Sandbox環境では単なるパス文字列には次回起動後の書き込み権限が無いため、
    /// security-scoped bookmarkも一緒に保存し、復元時にそれを解決してアクセス権を
    /// 取り戻す（`bookmarkData`が無い/解決できない場合は`originalPath`を表示用に使う）。
    struct Meta: Codable {
        let originalPath: String
        let bookmarkData: Data?
    }

    /// 保存済みドキュメントの場合のみ、元々どのファイルに紐づいていたかを書いておく。
    /// 復元時に「どこへ保存し直すべきか」を提案するために使う。
    static func writeMeta(for id: UUID, originalURL: URL?) {
        guard let originalURL else { return }
        let bookmarkData = try? originalURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let meta = Meta(originalPath: originalURL.path, bookmarkData: bookmarkData)
        guard let data = try? PropertyListEncoder().encode(meta) else { return }
        try? data.write(to: metaURL(for: id))
    }

    static func readMeta(for backupURL: URL) -> Meta? {
        guard let id = UUID(uuidString: backupURL.deletingPathExtension().lastPathComponent) else { return nil }
        guard let data = try? Data(contentsOf: metaURL(for: id)) else { return nil }
        return try? PropertyListDecoder().decode(Meta.self, from: data)
    }

    static func removeBackup(for id: UUID) {
        try? FileManager.default.removeItem(at: backupURL(for: id))
        try? FileManager.default.removeItem(at: metaURL(for: id))
    }

    /// 前回起動時に取り残されたバックアップ（＝正常に閉じられなかったドキュメント）の一覧。
    static func orphanedBackups() -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return entries.filter { $0.pathExtension == "bak" }
    }
}
