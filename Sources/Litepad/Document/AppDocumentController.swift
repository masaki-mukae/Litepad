import AppKit

/// Info.plistのCFBundleDocumentTypesに頼らず、常に`LitepadDocument`をドキュメントクラスとして使う。
/// SPM実行ファイル（.appバンドルではない）で動かすための最小構成。
final class AppDocumentController: NSDocumentController {
    static let documentTypeName = "LitepadText"

    override var defaultType: String? {
        Self.documentTypeName
    }

    override var documentClassNames: [String] {
        [NSStringFromClass(LitepadDocument.self)]
    }

    override func documentClass(forType typeName: String) -> AnyClass? {
        LitepadDocument.self
    }

    override func typeForContents(of url: URL) throws -> String {
        Self.documentTypeName
    }
}
