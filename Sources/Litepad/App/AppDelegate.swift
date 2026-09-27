import AppKit

/// メニュー構築のみを担当する。ファイルの新規作成・開く・保存・保存確認・Undo Managerの提供は
/// すべてNSDocument/NSDocumentControllerの標準機構に委ねる。
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        offerAutosaveRecoveryIfNeeded()
        if NSDocumentController.shared.documents.isEmpty {
            _ = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
        }
    }

    /// 前回起動時に正常に閉じられなかったドキュメントの自動保存バックアップが残っていれば、
    /// 復元するか破棄するかをユーザーに確認する（サクラエディタの自動保存・復元機能相当）。
    private func offerAutosaveRecoveryIfNeeded() {
        let backups = AutoSaveManager.orphanedBackups()
        guard !backups.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "自動保存されたファイルがあります"
        alert.informativeText = "前回終了時に保存されていなかった変更が\(backups.count)件見つかりました。復元しますか？"
        alert.addButton(withTitle: "復元")
        alert.addButton(withTitle: "破棄")
        let response = alert.runModal()

        for backupURL in backups {
            if response == .alertFirstButtonReturn {
                recoverBackup(at: backupURL)
            }
            let idString = backupURL.deletingPathExtension().lastPathComponent
            if let uuid = UUID(uuidString: idString) {
                AutoSaveManager.removeBackup(for: uuid)
            }
        }
    }

    private func recoverBackup(at backupURL: URL) {
        guard let recoveredBuffer = try? DocumentBuffer(contentsOf: backupURL) else { return }
        let originalPath = AutoSaveManager.readMeta(for: backupURL)

        let document = LitepadDocument()
        document.adoptRecoveredContent(recoveredBuffer, originalPath: originalPath)
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Menu

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "環境設定…", action: #selector(showPreferences(_:)), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Litepadを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "ファイル")
        let newItem = fileMenu.addItem(withTitle: "新規", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        newItem.target = NSDocumentController.shared
        fileMenu.addItem(withTitle: "開く…", action: #selector(openDocument(_:)), keyEquivalent: "o").target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "保存", action: #selector(saveCurrentDocument(_:)), keyEquivalent: "s").target = self
        let saveAsItem = fileMenu.addItem(withTitle: "名前を付けて保存…", action: #selector(saveCurrentDocumentAs(_:)), keyEquivalent: "s")
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        saveAsItem.target = self
        fileMenu.addItem(.separator())
        let encodingItem = NSMenuItem(title: "文字コード", action: nil, keyEquivalent: "")
        let encodingMenu = NSMenu(title: "文字コード")
        encodingMenu.delegate = self
        for kind in TextEncodingKind.allCases {
            let item = encodingMenu.addItem(withTitle: kind.displayName, action: #selector(convertEncoding(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind
        }
        encodingItem.submenu = encodingMenu
        fileMenu.addItem(encodingItem)
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "閉じる", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "編集")
        editMenu.addItem(withTitle: "取り消す", action: #selector(TextCanvasView.undo(_:)), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "やり直す", action: #selector(TextCanvasView.redo(_:)), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "すべてを選択", action: #selector(NSStandardKeyBindingResponding.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let findMenuItem = NSMenuItem()
        let findMenu = NSMenu(title: "検索")
        findMenu.addItem(withTitle: "検索と置換…", action: #selector(showFindPanel(_:)), keyEquivalent: "f").target = self
        let grepItem = findMenu.addItem(withTitle: "Grep（フォルダ内検索）…", action: #selector(showGrepWindow(_:)), keyEquivalent: "f")
        grepItem.keyEquivalentModifierMask = [.command, .shift]
        grepItem.target = self
        findMenu.addItem(.separator())
        let outlineItem = findMenu.addItem(withTitle: "アウトライン…", action: #selector(showOutlineWindow(_:)), keyEquivalent: "o")
        outlineItem.keyEquivalentModifierMask = [.command, .shift]
        outlineItem.target = self
        findMenuItem.submenu = findMenu
        mainMenu.addItem(findMenuItem)

        // ブックマーク。本家サクラエディタのCtrl+F2（切替）/F2（次へ）/Shift+F2（前へ）に倣う
        // （Macでは修飾キーだけCtrlをCommandに読み替える）。ターゲット未指定のままにして、
        // ファーストレスポンダーである`TextCanvasView`自身へ直接届くようにする
        // （Undo/Redoと同じ、複数ホップの解決を必要としない一番信頼できるパターン）。
        let bookmarkMenuItem = NSMenuItem()
        let bookmarkMenu = NSMenu(title: "ブックマーク")
        let toggleBookmarkItem = bookmarkMenu.addItem(
            withTitle: "ブックマークの切替",
            action: #selector(TextCanvasView.toggleBookmark(_:)),
            keyEquivalent: String(UnicodeScalar(NSF2FunctionKey)!)
        )
        toggleBookmarkItem.keyEquivalentModifierMask = [.command]
        bookmarkMenu.addItem(
            withTitle: "次のブックマーク",
            action: #selector(TextCanvasView.jumpToNextBookmark(_:)),
            keyEquivalent: String(UnicodeScalar(NSF2FunctionKey)!)
        ).keyEquivalentModifierMask = []
        bookmarkMenu.addItem(
            withTitle: "前のブックマーク",
            action: #selector(TextCanvasView.jumpToPreviousBookmark(_:)),
            keyEquivalent: String(UnicodeScalar(NSF2FunctionKey)!)
        ).keyEquivalentModifierMask = [.shift]
        bookmarkMenuItem.submenu = bookmarkMenu
        mainMenu.addItem(bookmarkMenuItem)

        // ウィンドウメニュー。NSApp.windowsMenuに割り当てることで、タブ一覧・
        // 「タブバーを表示」・「すべてのウィンドウを統合」などOS標準の項目が自動的に追加される。
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "ウィンドウ")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "拡大/縮小", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        let nextTabItem = windowMenu.addItem(withTitle: "次のタブを選択", action: #selector(NSWindow.selectNextTab(_:)), keyEquivalent: "]")
        nextTabItem.keyEquivalentModifierMask = [.command, .shift]
        let prevTabItem = windowMenu.addItem(withTitle: "前のタブを選択", action: #selector(NSWindow.selectPreviousTab(_:)), keyEquivalent: "[")
        prevTabItem.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "すべてを手前に移動", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    /// `NSDocumentController.openDocument(_:)`はInfo.plistのCFBundleDocumentTypes前提の
    /// メニュー検証で無効化されてしまう（本アプリはInfo.plist無しのSPM実行ファイルのため）。
    /// そのため自前でパネルを出し、`openDocument(withContentsOf:display:completionHandler:)`で開く。
    @objc private func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error {
                        NSAlert(error: error).runModal()
                    }
                }
            }
        }
    }

    /// メニュー項目を`NSDocument.save(_:)`へnilターゲットで委ねると、ネイティブのウィンドウ
    /// タブ機構と組み合わさった際にキー入力（⌘S）がメニューの自動有効化判定に正しく
    /// 届かないことがあったため、明示的に`currentDocument`へ転送する。
    @objc private func saveCurrentDocument(_ sender: Any?) {
        NSDocumentController.shared.currentDocument?.save(sender)
    }

    @objc private func saveCurrentDocumentAs(_ sender: Any?) {
        NSDocumentController.shared.currentDocument?.saveAs(sender)
    }

    @objc private func showPreferences(_ sender: Any?) {
        PreferencesWindowController.shared.show()
    }

    @objc private func showGrepWindow(_ sender: Any?) {
        GrepWindowController.shared.show()
    }

    @objc private func showOutlineWindow(_ sender: Any?) {
        // アウトラインウィンドウ自身がキーウィンドウになる前に、まだドキュメント側が
        // キーである今のうちに対象を確定させる（OutlineWindowController内のコメント参照）。
        let document = NSDocumentController.shared.currentDocument as? LitepadDocument
        OutlineWindowController.shared.show(for: document)
    }

    @objc private func showFindPanel(_ sender: Any?) {
        guard let document = NSDocumentController.shared.currentDocument as? LitepadDocument else { return }
        let controller = document.windowControllers.compactMap { $0 as? DocumentWindowController }.first
        controller?.showFindPanel()
    }

    @objc private func convertEncoding(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? TextEncodingKind,
              let document = NSDocumentController.shared.currentDocument as? LitepadDocument else { return }
        document.convertEncoding(to: kind)
    }

    /// 「文字コード」サブメニューを開くたびに、現在のドキュメントのエンコーディングへ
    /// チェックマークを付け直す。
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "文字コード" else { return }
        let current = (NSDocumentController.shared.currentDocument as? LitepadDocument)?.buffer.encoding
        for item in menu.items {
            item.state = (item.representedObject as? TextEncodingKind) == current ? .on : .off
        }
    }
}
