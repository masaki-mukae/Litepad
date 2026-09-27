import AppKit

// NSDocumentController.sharedが最初にアクセスされる前に、独自サブクラスを生成しておく必要がある
// （既定のNSDocumentControllerが先に生成されると、Info.plist無しではLitepadDocumentを解決できない）。
let documentController = AppDocumentController()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
