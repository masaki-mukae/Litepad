import AppKit

/// アプリ全体の環境設定。UserDefaultsに永続化し、変更時に`didChangeNotification`を発行する。
/// 開いている全ドキュメントの`TextCanvasView`はこの通知を購読して再描画する。
final class AppSettings {
    static let shared = AppSettings()
    static let didChangeNotification = Notification.Name("AppSettingsDidChange")

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let fontName = "editorFontName"
        static let fontSize = "editorFontSize"
        static let tabWidth = "editorTabWidth"
        static let showLineNumbers = "editorShowLineNumbers"
    }

    private init() {}

    /// 空文字列は「システム標準の等幅フォント」を意味する。
    var fontName: String {
        get { defaults.string(forKey: Keys.fontName) ?? "" }
        set {
            defaults.set(newValue, forKey: Keys.fontName)
            notifyChanged()
        }
    }

    var fontSize: Double {
        get {
            let value = defaults.double(forKey: Keys.fontSize)
            return value > 0 ? value : 14
        }
        set {
            defaults.set(newValue, forKey: Keys.fontSize)
            notifyChanged()
        }
    }

    /// タブ1つ分の見た目の幅（スペース換算の文字数）。
    var tabWidth: Int {
        get {
            let value = defaults.integer(forKey: Keys.tabWidth)
            return value > 0 ? value : 4
        }
        set {
            defaults.set(newValue, forKey: Keys.tabWidth)
            notifyChanged()
        }
    }

    /// 行番号の表示・非表示（サクラエディタの「行番号を表示」設定に相当）。
    var showLineNumbers: Bool {
        get {
            defaults.object(forKey: Keys.showLineNumbers) == nil ? true : defaults.bool(forKey: Keys.showLineNumbers)
        }
        set {
            defaults.set(newValue, forKey: Keys.showLineNumbers)
            notifyChanged()
        }
    }

    var font: NSFont {
        if fontName.isEmpty {
            return NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        }
        return NSFont(name: fontName, size: CGFloat(fontSize)) ?? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
    }

    func resetToDefaults() {
        defaults.removeObject(forKey: Keys.fontName)
        defaults.removeObject(forKey: Keys.fontSize)
        defaults.removeObject(forKey: Keys.tabWidth)
        defaults.removeObject(forKey: Keys.showLineNumbers)
        notifyChanged()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
