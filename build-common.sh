# build-app.sh（直接配布用）とbuild-app-store.sh（Mac App Store提出用）の両方が使う、
# .appバンドルのInfo.plist生成だけを共有する。署名方法やパッケージング（zip/pkg）は
# 配布経路によって大きく異なるため、あえて共通化せずそれぞれのスクリプトに任せる。
# `source build-common.sh`で読み込んで使う（単体では実行しない）。

# マーケティングバージョンはこのファイルで一元管理する（リリース時にここだけ更新する）。
LITEPAD_VERSION="0.3.2"
# ビルド番号はコミット数から自動算出し、手動管理せずとも再提出のたびに単調増加させる
# （App Store Connectは同じCFBundleVersionでの再アップロードを拒否するため）。
LITEPAD_BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# 引数: $1 = 書き出し先のInfo.plistパス（例: "$CONTENTS/Info.plist"）
write_litepad_info_plist() {
    local dest="$1"
    cat > "$dest" <<EOF
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
    <string>${LITEPAD_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${LITEPAD_BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <!-- App Store Connectの審査提出に必須のカテゴリ。開発者向けツール寄りの機能
         （シンタックスハイライト・Grep・アウトライン）を踏まえてDeveloper Toolsを選択。
         App Store Connect側のプライマリカテゴリ設定でいつでも変更できる。 -->
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Masaki Mukae. All rights reserved.</string>
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
                <string>public.bash-script</string>
                <string>public.zsh-script</string>
                <string>public.perl-script</string>
                <string>public.php-script</string>
                <string>com.sun.java-source</string>
                <string>public.json</string>
                <string>public.yaml</string>
                <string>public.toml</string>
                <string>public.xml</string>
                <string>public.html</string>
                <string>public.css</string>
                <string>net.daringfireball.markdown</string>
                <string>com.netscape.javascript-source</string>
                <string>com.microsoft.typescript</string>
                <string>org.iso.sql</string>
                <string>com.apple.rez-source</string>
                <!-- ログファイル。com.apple.logはpublic.plain-textを継承しているため
                     本来は省略しても一致するが、確実性のため明示しておく。 -->
                <string>com.apple.log</string>
                <!-- .ts/.fsは、macOS標準では別の意味のUTI（MPEG-2 TSビデオ／GLSLの
                     フラグメントシェーダ）が割り当てられてしまっている拡張子。
                     TypeScript・F#のソースコードとして開けるように、あえて追加する
                     （VS Codeなど他の主要エディタも同様の対応をしている）。 -->
                <string>public.mpeg-2-transport-stream</string>
                <string>org.khronos.glsl.fragment-shader</string>
                <!-- 以下はmacOSに対応するUTIが存在しない拡張子向けに、下のUTExportedTypeDeclarations
                     で独自にUTIをエクスポートして定義したもの（いずれもpublic.source-codeを
                     継承させてあるので、本来はここに書かなくても一致するが、対応拡張子を
                     一覧で把握しやすいよう明示しておく）。 -->
                <string>com.litepad.source.go</string>
                <string>com.litepad.source.rust</string>
                <string>com.litepad.source.kotlin</string>
                <string>com.litepad.source.kotlin-script</string>
                <string>com.litepad.source.csharp</string>
                <string>com.litepad.source.dart</string>
                <string>com.litepad.source.scala</string>
                <string>com.litepad.source.groovy</string>
                <string>com.litepad.source.gradle</string>
                <string>com.litepad.source.lua</string>
                <string>com.litepad.source.elixir</string>
                <string>com.litepad.source.erlang</string>
                <string>com.litepad.source.haskell</string>
                <string>com.litepad.source.clojure</string>
                <string>com.litepad.source.clojurescript</string>
                <string>com.litepad.source.julia</string>
                <string>com.litepad.source.solidity</string>
                <string>com.litepad.source.vue</string>
                <string>com.litepad.source.jsx</string>
                <string>com.litepad.source.commonjs</string>
                <string>com.litepad.source.python-stub</string>
                <string>com.litepad.source.properties</string>
                <string>com.litepad.source.conf</string>
            </array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <!-- macOSに標準のUTIが存在しない主要プログラミング言語の拡張子を、Litepadが
             ソースコードとして開けるようにエクスポートする。1つの拡張子に複数アプリが
             別々のUTIをエクスポートすると、その拡張子の種別判定はシステム全体で
             最後に登録した側に依存するが、エディタで開く分には実害が無い
             （他のエディタ・IDEも同様の対応をしている）。 -->
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.go</string>
            <key>UTTypeDescription</key><string>Go Source</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>go</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.rust</string>
            <key>UTTypeDescription</key><string>Rust Source</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>rs</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.kotlin</string>
            <key>UTTypeDescription</key><string>Kotlin Source</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>kt</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.kotlin-script</string>
            <key>UTTypeDescription</key><string>Kotlin Script</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>kts</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.csharp</string>
            <key>UTTypeDescription</key><string>C# Source</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>cs</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.dart</string>
            <key>UTTypeDescription</key><string>Dart Source</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>dart</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.scala</string>
            <key>UTTypeDescription</key><string>Scala Source</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>scala</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.groovy</string>
            <key>UTTypeDescription</key><string>Groovy Source</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>groovy</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.gradle</string>
            <key>UTTypeDescription</key><string>Gradle Build Script</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>gradle</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.lua</string>
            <key>UTTypeDescription</key><string>Lua Source</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>lua</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.elixir</string>
            <key>UTTypeDescription</key><string>Elixir Source</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>ex</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.erlang</string>
            <key>UTTypeDescription</key><string>Erlang Source</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>erl</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.haskell</string>
            <key>UTTypeDescription</key><string>Haskell Source</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>hs</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.clojure</string>
            <key>UTTypeDescription</key><string>Clojure Source</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>clj</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.clojurescript</string>
            <key>UTTypeDescription</key><string>ClojureScript Source</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>cljs</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.julia</string>
            <key>UTTypeDescription</key><string>Julia Source</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>jl</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.solidity</string>
            <key>UTTypeDescription</key><string>Solidity Source</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>sol</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.vue</string>
            <key>UTTypeDescription</key><string>Vue Component</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>vue</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.jsx</string>
            <key>UTTypeDescription</key><string>JSX Source</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>jsx</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.commonjs</string>
            <key>UTTypeDescription</key><string>CommonJS Source</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>cjs</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.python-stub</string>
            <key>UTTypeDescription</key><string>Python Stub</string>
            <key>UTTypeConformsTo</key><array><string>public.python-script</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>pyi</string><string>pyw</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.properties</string>
            <key>UTTypeDescription</key><string>Java Properties</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>properties</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.litepad.source.conf</string>
            <key>UTTypeDescription</key><string>Configuration File</string>
            <key>UTTypeConformsTo</key><array><string>public.source-code</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>conf</string></array></dict>
        </dict>
    </array>
</dict>
</plist>
EOF
}
