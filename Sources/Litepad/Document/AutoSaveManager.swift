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

    /// バックアップと一緒に、元々どのファイルに紐づいていたか（保存済みドキュメントの場合）を
    /// テキストファイルとして書いておく。復元時に「どこへ保存し直すべきか」を提案するために使う。
    static func writeMeta(for id: UUID, originalPath: String?) {
        guard let originalPath else { return }
        try? originalPath.write(to: metaURL(for: id), atomically: true, encoding: .utf8)
    }

    static func readMeta(for backupURL: URL) -> String? {
        guard let id = UUID(uuidString: backupURL.deletingPathExtension().lastPathComponent) else { return nil }
        return try? String(contentsOf: metaURL(for: id), encoding: .utf8)
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
