#!/bin/bash
# Litepadをビルドし、~/Applications/Litepad.appとしてインストールする。
# Finder/Spotlight/Dockから通常のMacアプリとして起動できるようにするための最小限の.appバンドル化。
set -e
cd "$(dirname "$0")"

echo "ビルド中(リリース構成)..."
swift build -c release

APP_DIR="$HOME/Applications/Litepad.app"
CONTENTS="$APP_DIR/Contents"

echo "アプリバンドルを作成中: $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/ja.lproj"
cp .build/release/Litepad "$CONTENTS/MacOS/Litepad"
cp Resources/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"
# ja.lprojを実体として置いておくことで、システムに「日本語ローカライズを持つアプリ」と
# 確実に認識させる（保存パネルのボタンや、編集メニューに自動追加される「絵文字と記号」
# 「音声入力を開始」などが日本語で表示されるようになる）。
touch "$CONTENTS/Resources/ja.lproj/InfoPlist.strings"

cat > "$CONTENTS/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Litepad</string>
    <key>CFBundleIdentifier</key>
    <string>com.litepad.app</string>
    <key>CFBundleName</key>
    <string>Litepad</string>
    <key>CFBundleDisplayName</key>
    <string>Litepad</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>ja</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>ja</string>
    </array>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>テキスト</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <!-- LitepadはTextEdit等を置き換える既定アプリではなく、あくまで選択肢の
                 ひとつ（Finderの「このアプリケーションで開く」に出す）として登録する。
                 Owner/Defaultにすると、インストールしただけでユーザーの意思に反して
                 既定のテキストエディタを奪ってしまう。 -->
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.plain-text</string>
                <string>public.text</string>
                <string>public.utf8-plain-text</string>
                <string>public.utf16-plain-text</string>
                <string>public.source-code</string>
                <string>public.swift-source</string>
                <string>public.c-source</string>
                <string>public.c-plus-plus-source</string>
                <string>public.c-header</string>
                <string>public.c-plus-plus-header</string>
                <string>public.objective-c-source</string>
                <string>public.objective-c-plus-plus-source</string>
                <string>public.python-script</string>
                <string>public.ruby-script</string>
                <string>public.shell-script</string>
                <string>public.perl-script</string>
                <string>public.php-script</string>
                <string>com.sun.java-source</string>
                <string>public.json</string>
                <string>public.yaml</string>
                <string>public.xml</string>
                <string>public.html</string>
                <string>public.css</string>
                <string>net.daringfireball.markdown</string>
                <string>com.netscape.javascript-source</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# ad-hoc署名(Apple公証ではない)を、App Sandbox entitlementsを添えて付与する。
# 無署名のままだと、ブラウザ経由でダウンロードしたzipを展開した際にmacOS Ventura以降で
# 「ファイルが壊れています」と表示され開けなくなる。ad-hoc署名があれば
# 「開発元が未確認」の警告に変わり、右クリック→「開く」で起動できるようになる。
# entitlementsはApp Store配布を見据えてサンドボックス化のため常時付与する
# （直接配布のad-hoc署名でもサンドボックス自体は有効にできる）。
echo "ad-hoc署名(サンドボックスentitlements付き)を付与中..."
codesign --force --deep --sign - --entitlements Resources/Litepad.entitlements "$APP_DIR"

echo "完了: SpotlightまたはFinderの ~/Applications から「Litepad」を起動できます。"
