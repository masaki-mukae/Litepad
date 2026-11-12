#!/bin/bash
# Mac App Store提出用の署名済み.pkgを作成する。build-app.sh（直接配布・ad-hoc署名）とは
# 別経路: Apple Distribution証明書でアプリ本体を署名し、プロビジョニングプロファイルを
# 埋め込み、3rd Party Mac Developer Installer証明書でインストーラ(.pkg)に署名する。
#
# 事前準備（developer.apple.com/account で一度だけ行う。詳細はCLAUDE.md参照）:
#   1. App ID "com.litepad.app" を登録
#   2. 「Apple Distribution」証明書を作成（Xcode > 設定 > Accounts > Manage Certificates）
#   3. 「Mac Installer Distribution」証明書を作成（developer.apple.com、CSR必須）
#   4. Mac App Store用プロビジョニングプロファイルを作成・ダウンロード
#
# 出力: /tmp/Litepad.pkg（App Store Connect純正のアップロードツール「Transporter」で
# アップロードする。Transporter.appはMac App Storeから無料で入手できる）。
set -e
cd "$(dirname "$0")"
source "$(dirname "$0")/build-common.sh"

# ダウンロードしたプロビジョニングプロファイルのパス。環境変数で上書き可能
# （アカウント固有の情報を含むためリポジトリにはコミットしていない）。
PROVISION_PROFILE="${PROVISION_PROFILE:-$HOME/Downloads/Litepad_Mac_App_Store.provisionprofile}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-Apple Distribution: Masaki Mukae (NTJSZ2BQNS)}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-3rd Party Mac Developer Installer: Masaki Mukae (NTJSZ2BQNS)}"

if [ ! -f "$PROVISION_PROFILE" ]; then
    echo "エラー: プロビジョニングプロファイルが見つかりません: $PROVISION_PROFILE" >&2
    echo "  developer.apple.com/account > Profiles でダウンロードするか、" >&2
    echo "  PROVISION_PROFILE=<path> ./build-app-store.sh のように環境変数で指定してください。" >&2
    exit 1
fi

echo "ビルド中(リリース構成)..."
swift build -c release

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
APP_DIR="$BUILD_DIR/Litepad.app"
CONTENTS="$APP_DIR/Contents"

echo "アプリバンドルを作成中: $APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/ja.lproj"
cp .build/release/Litepad "$CONTENTS/MacOS/Litepad"
cp Resources/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"
touch "$CONTENTS/Resources/ja.lproj/InfoPlist.strings"
write_litepad_info_plist "$CONTENTS/Info.plist"
cp "$PROVISION_PROFILE" "$CONTENTS/embedded.provisionprofile"

echo "Apple Distribution証明書で署名中..."
codesign --force --deep --sign "$APP_SIGN_IDENTITY" \
    --entitlements Resources/LitepadMacAppStore.entitlements \
    --options runtime \
    "$APP_DIR"

echo "署名を検証中..."
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

OUT_PKG="/tmp/Litepad.pkg"
echo "インストーラ(.pkg)を作成・署名中..."
productbuild --component "$APP_DIR" /Applications \
    --sign "$INSTALLER_SIGN_IDENTITY" \
    "$OUT_PKG"

echo
echo "完了: $OUT_PKG"
echo "次の手順: 「Transporter」アプリ（Mac App Storeから入手）にこのpkgをドラッグ&ドロップしてアップロードしてください。"
