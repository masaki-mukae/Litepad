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
</dict>
</plist>
EOF

# ad-hoc署名(Apple公証ではない)を付与する。無署名のままだと、ブラウザ経由で
# ダウンロードしたzipを展開した際にmacOS Ventura以降で「ファイルが壊れています」と
# 表示され開けなくなる。ad-hoc署名があれば「開発元が未確認」の警告に変わり、
# 右クリック→「開く」で起動できるようになる。
echo "ad-hoc署名を付与中..."
codesign --force --deep --sign - "$APP_DIR"

echo "完了: SpotlightまたはFinderの ~/Applications から「Litepad」を起動できます。"
