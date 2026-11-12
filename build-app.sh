#!/bin/bash
# Litepadをビルドし、~/Applications/Litepad.appとしてインストールする。
# Finder/Spotlight/Dockから通常のMacアプリとして起動できるようにするための最小限の.appバンドル化。
set -e
cd "$(dirname "$0")"

source "$(dirname "$0")/build-common.sh"

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

write_litepad_info_plist "$CONTENTS/Info.plist"

# ad-hoc署名(Apple公証ではない)を、App Sandbox entitlementsを添えて付与する。
# 無署名のままだと、ブラウザ経由でダウンロードしたzipを展開した際にmacOS Ventura以降で
# 「ファイルが壊れています」と表示され開けなくなる。ad-hoc署名があれば
# 「開発元が未確認」の警告に変わり、右クリック→「開く」で起動できるようになる。
# entitlementsはApp Store配布を見据えてサンドボックス化のため常時付与する
# （直接配布のad-hoc署名でもサンドボックス自体は有効にできる）。
echo "ad-hoc署名(サンドボックスentitlements付き)を付与中..."
codesign --force --deep --sign - --entitlements Resources/Litepad.entitlements "$APP_DIR"

echo "完了: SpotlightまたはFinderの ~/Applications から「Litepad」を起動できます。"
