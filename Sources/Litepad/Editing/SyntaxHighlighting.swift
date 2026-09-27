import Foundation

enum SyntaxTokenKind {
    case keyword
    /// サクラエディタのSSTRING/WSTRING相当。クォート種別によって色を分ける。
    case singleQuoteString
    case doubleQuoteString
    case comment
    case number
    case url
}

struct SyntaxToken {
    let range: Range<Int>
    let kind: SyntaxTokenKind
}

/// 文字列内のクォート文字自身をエスケープする方式。
/// - backslash: `"a\"b"` のようにバックスラッシュでエスケープする（C/Java/Perl等）
/// - doubledQuote: `'it''s'` のようにクォートを2つ重ねてエスケープする（SQL/Pascal/VB等）
enum StringEscapeStyle {
    case backslash
    case doubledQuote
}

struct BlockCommentPair {
    let start: String
    let end: String
}

/// 行頭時点での複数行にまたがる状態（ブロックコメント／複数行文字列）。
/// 巨大ファイルでも編集した行以降だけ遅延再計算できるよう、行ごとにキャッシュする。
enum LineLexState: Equatable {
    case normal
    case blockComment(pairIndex: Int)
    case tripleQuoteString(delimiter: String)
}

/// 言語ごとのハイライト規則。正確な構文解析ではなく、サクラエディタの強調表示に相当する
/// 見た目の色分け（キーワード／コメント／文字列／数値／URL）が目的の軽量な定義。
struct LanguageDefinition {
    var keywords: Set<String> = []
    var caseInsensitiveKeywords: Bool = false
    var lineCommentPrefixes: [String] = []
    var blockComments: [BlockCommentPair] = []
    var stringDelimiters: Set<Character> = []
    var stringEscapeStyle: StringEscapeStyle = .backslash
    /// Pythonの `"""` `'''` のような複数行文字列。
    var tripleQuoteDelimiters: [String] = []
    /// COBOLのような「行の特定列がマーカーならその行全体がコメント」というルール。
    var fixedColumnCommentColumn: Int?
    var fixedColumnCommentMarkers: Set<Character>?
    /// TeXの `\section` のような、プレフィックス文字1つ+英字列をキーワードとして扱う言語向け。
    var commandPrefix: Character?
    /// Pythonのように、行末の `:` がブロック開始（スマートインデントで1段深くする対象）になる言語向け。
    var colonTriggersIndent: Bool = false

    static func detect(forExtension ext: String) -> LanguageDefinition? {
        byExtension[ext.lowercased()]
    }

    // サクラエディタ2.4.3が標準搭載する16種類の言語タイプ（Basis/Others/CorbaIdl/Erlangは
    // 実ファイルタイプとして登録されていないため対象外）に、Mac版として実用上あると便利な
    // 現代的なC系言語（JS/TS/Swift等）を追加している。
    private static let byExtension: [String: LanguageDefinition] = [
        "c": .cpp, "h": .cpp, "cpp": .cpp, "cxx": .cpp, "cc": .cpp, "cp": .cpp,
        "hpp": .cpp, "hxx": .cpp, "hh": .cpp, "hp": .cpp, "rc": .cpp, "hm": .cpp,
        "java": .java, "jav": .java,
        "html": .html, "htm": .html, "shtml": .html, "plg": .html,
        "sql": .sql, "plsql": .sql,
        "cbl": .cobol, "cpy": .cobol, "pco": .cobol, "cob": .cobol,
        "asm": .asm,
        "awk": .awk,
        "bat": .dosBatch,
        "pas": .pascal, "dpr": .pascal,
        "tex": .tex, "ltx": .tex, "sty": .tex, "bib": .tex, "blg": .tex, "aux": .tex,
        "bbl": .tex, "toc": .tex, "lof": .tex, "lot": .tex, "idx": .tex, "ind": .tex, "glo": .tex,
        "pl": .perl, "pm": .perl, "cgi": .perl,
        "py": .python,
        "bas": .vb, "frm": .vb, "cls": .vb, "ctl": .vb, "vb": .vb,
        "ini": .ini, "inf": .ini, "cnf": .ini,
        // Sakura本家には無いが、現代のMac用エディタとして対応しておくと実用的な言語。
        "js": .cLikeModern, "jsx": .cLikeModern, "ts": .cLikeModern, "tsx": .cLikeModern,
        "swift": .cLikeModern, "kt": .cLikeModern, "go": .cLikeModern, "rs": .cLikeModern,
    ]

    // MARK: - C/C++

    static let cpp = LanguageDefinition(
        keywords: [
            "auto", "break", "case", "char", "const", "continue", "default", "do", "double",
            "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long",
            "register", "restrict", "return", "short", "signed", "sizeof", "static", "struct",
            "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "class",
            "namespace", "template", "typename", "public", "private", "protected", "virtual",
            "override", "new", "delete", "this", "friend", "using", "try", "catch", "throw",
            "explicit", "operator", "mutable", "constexpr", "nullptr", "bool", "true", "false",
            "static_cast", "dynamic_cast", "const_cast", "reinterpret_cast", "noexcept",
        ],
        lineCommentPrefixes: ["//"],
        blockComments: [
            BlockCommentPair(start: "/*", end: "*/"),
            // サクラエディタは無効化されたプリプロセッサブロックもコメット同様に強調表示する。
            BlockCommentPair(start: "#if 0", end: "#endif"),
        ],
        stringDelimiters: ["\"", "'"]
    )

    static let cLikeModern = LanguageDefinition(
        keywords: cpp.keywords.union([
            "let", "func", "fn", "var", "import", "export", "async", "await", "interface",
            "type", "package", "module", "extends", "implements", "super", "null", "undefined",
            "typeof", "instanceof", "in", "of", "guard", "defer", "where", "protocol", "mut",
            "impl", "trait", "match", "yield", "with",
        ]),
        lineCommentPrefixes: ["//"],
        blockComments: [BlockCommentPair(start: "/*", end: "*/")],
        stringDelimiters: ["\"", "'"]
    )

    // MARK: - Java

    static let java = LanguageDefinition(
        keywords: [
            "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class",
            "const", "continue", "default", "do", "double", "else", "enum", "extends", "final",
            "finally", "float", "for", "goto", "if", "implements", "import", "instanceof", "int",
            "interface", "long", "native", "new", "package", "private", "protected", "public",
            "record", "return", "sealed", "short", "static", "strictfp", "super", "switch",
            "synchronized", "this", "throw", "throws", "transient", "try", "var", "void",
            "volatile", "while", "true", "false", "null", "yield", "permits",
        ],
        lineCommentPrefixes: ["//"],
        blockComments: [BlockCommentPair(start: "/*", end: "*/")],
        stringDelimiters: ["\"", "'"]
    )

    // MARK: - HTML

    static let html = LanguageDefinition(
        keywords: [
            "html", "head", "body", "title", "meta", "link", "script", "style", "div", "span",
            "p", "a", "img", "ul", "ol", "li", "table", "tr", "td", "th", "thead", "tbody",
            "tfoot", "form", "input", "button", "label", "select", "option", "textarea",
            "h1", "h2", "h3", "h4", "h5", "h6", "br", "hr", "strong", "em", "b", "i", "u",
            "nav", "header", "footer", "section", "article", "aside", "main", "canvas",
            "video", "audio", "source", "iframe", "svg", "path", "doctype",
        ],
        caseInsensitiveKeywords: true,
        blockComments: [BlockCommentPair(start: "<!--", end: "-->")],
        stringDelimiters: ["\"", "'"]
    )

    // MARK: - SQL (PL/SQL)

    static let sql = LanguageDefinition(
        keywords: [
            "select", "from", "where", "insert", "into", "values", "update", "set", "delete",
            "create", "table", "alter", "drop", "join", "inner", "left", "right", "outer", "full",
            "on", "group", "by", "order", "having", "as", "distinct", "and", "or", "not", "null",
            "is", "in", "like", "between", "limit", "offset", "union", "all", "exists", "case",
            "when", "then", "else", "end", "primary", "key", "foreign", "references", "default",
            "unique", "index", "view", "trigger", "procedure", "function", "begin", "commit",
            "rollback", "transaction", "grant", "revoke", "with", "cascade", "constraint", "check",
        ],
        caseInsensitiveKeywords: true,
        lineCommentPrefixes: ["--"],
        blockComments: [BlockCommentPair(start: "/*", end: "*/")],
        stringDelimiters: ["'"],
        stringEscapeStyle: .doubledQuote
    )

    // MARK: - COBOL

    static let cobol = LanguageDefinition(
        keywords: [
            "IDENTIFICATION", "DIVISION", "PROGRAM-ID", "ENVIRONMENT", "CONFIGURATION",
            "SOURCE-COMPUTER", "OBJECT-COMPUTER", "DATA", "WORKING-STORAGE", "SECTION",
            "PROCEDURE", "PIC", "PICTURE", "MOVE", "TO", "FROM", "PERFORM", "UNTIL", "VARYING",
            "IF", "ELSE", "END-IF", "COMPUTE", "ADD", "SUBTRACT", "MULTIPLY", "DIVIDE",
            "DISPLAY", "ACCEPT", "STOP", "RUN", "CALL", "USING", "RETURNING", "OPEN", "CLOSE",
            "READ", "WRITE", "FILE", "RECORD", "VALUE", "OCCURS", "REDEFINES", "COPY", "EXIT",
            "GOBACK", "EVALUATE", "WHEN", "THRU", "INITIALIZE", "STRING", "UNSTRING", "INSPECT",
            "SET", "INDEXED", "BY",
        ],
        stringDelimiters: ["'", "\""],
        stringEscapeStyle: .doubledQuote,
        // サクラエディタはCOBOLのコメント行を固定列（7桁目=index6）の `*` / `D` で判定する。
        fixedColumnCommentColumn: 6,
        fixedColumnCommentMarkers: ["*", "D", "d"]
    )

    // MARK: - Pascal

    static let pascal = LanguageDefinition(
        keywords: [
            "program", "begin", "end", "var", "const", "type", "procedure", "function", "if",
            "then", "else", "case", "of", "while", "do", "repeat", "until", "for", "to",
            "downto", "array", "record", "set", "file", "packed", "with", "goto", "label",
            "uses", "unit", "interface", "implementation", "class", "object", "constructor",
            "destructor", "private", "public", "protected", "virtual", "override", "inherited",
            "nil", "true", "false", "and", "or", "not", "xor", "div", "mod", "in", "is", "as",
            "try", "except", "finally", "raise",
        ],
        caseInsensitiveKeywords: true,
        lineCommentPrefixes: ["//"],
        blockComments: [
            BlockCommentPair(start: "{", end: "}"),
            BlockCommentPair(start: "(*", end: "*)"),
        ],
        stringDelimiters: ["'"],
        stringEscapeStyle: .doubledQuote
    )

    // MARK: - Visual Basic

    static let vb = LanguageDefinition(
        keywords: [
            "Dim", "As", "Sub", "Function", "End", "If", "Then", "Else", "ElseIf", "For", "Next",
            "To", "Step", "While", "Wend", "Do", "Loop", "Until", "Select", "Case", "Exit",
            "Return", "Call", "Set", "New", "Nothing", "True", "False", "And", "Or", "Not", "Xor",
            "Public", "Private", "Protected", "Friend", "Static", "Const", "ByVal", "ByRef",
            "Optional", "ParamArray", "Class", "Module", "Type", "Enum", "Property", "Get", "Let",
            "With", "On", "Error", "Resume", "GoTo", "Redim", "Preserve", "Integer", "String",
            "Boolean", "Double", "Long", "Object", "Variant",
        ],
        caseInsensitiveKeywords: true,
        lineCommentPrefixes: ["'"],
        stringDelimiters: ["\""],
        stringEscapeStyle: .doubledQuote
    )

    // MARK: - Assembler

    static let asm = LanguageDefinition(
        keywords: [
            "mov", "push", "pop", "call", "ret", "jmp", "je", "jne", "jz", "jnz", "jg", "jl",
            "jge", "jle", "ja", "jb", "jc", "jo", "cmp", "test", "add", "sub", "mul", "div",
            "inc", "dec", "and", "or", "xor", "not", "shl", "shr", "lea", "nop", "int", "loop",
            "section", "global", "extern", "db", "dw", "dd", "dq", "equ", "org", "times",
            "align", "proc", "endp", "segment", "ends",
        ],
        caseInsensitiveKeywords: true,
        lineCommentPrefixes: [";"],
        stringDelimiters: ["\"", "'"]
    )

    // MARK: - Awk

    static let awk = LanguageDefinition(
        keywords: [
            "BEGIN", "END", "function", "if", "else", "while", "for", "do", "break", "continue",
            "next", "nextfile", "exit", "return", "delete", "getline", "print", "printf", "in",
            "split", "sub", "gsub", "match", "sprintf", "length", "substr", "index", "tolower",
            "toupper",
        ],
        lineCommentPrefixes: ["#"],
        stringDelimiters: ["\""]
    )

    // MARK: - MS-DOS batch

    static let dosBatch = LanguageDefinition(
        keywords: [
            "ECHO", "OFF", "ON", "SET", "IF", "ELSE", "GOTO", "CALL", "FOR", "IN", "DO", "EXIST",
            "NOT", "ERRORLEVEL", "PAUSE", "CLS", "EXIT", "SHIFT", "START", "TITLE", "CD", "DIR",
            "COPY", "DEL", "MOVE", "MD", "RD", "TYPE", "PATH", "SETLOCAL", "ENDLOCAL",
        ],
        caseInsensitiveKeywords: true,
        lineCommentPrefixes: ["REM "],
        stringDelimiters: ["\""]
    )

    // MARK: - Perl

    static let perl = LanguageDefinition(
        keywords: [
            "my", "our", "local", "sub", "if", "elsif", "else", "unless", "while", "until",
            "for", "foreach", "do", "last", "next", "redo", "return", "package", "use",
            "require", "qw", "print", "printf", "defined", "undef", "ref", "bless", "die",
            "warn", "eval", "wantarray", "shift", "unshift", "push", "pop", "splice", "keys",
            "values", "each", "exists", "delete", "and", "or", "not", "eq", "ne", "lt", "gt",
            "le", "ge", "cmp",
        ],
        lineCommentPrefixes: ["#"],
        stringDelimiters: ["\"", "'"]
    )

    // MARK: - Python

    static let python = LanguageDefinition(
        keywords: [
            "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class",
            "continue", "def", "del", "elif", "else", "except", "finally", "for", "from",
            "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass",
            "raise", "return", "try", "while", "with", "yield", "self",
        ],
        lineCommentPrefixes: ["#"],
        stringDelimiters: ["\"", "'"],
        tripleQuoteDelimiters: ["\"\"\"", "'''"],
        colonTriggersIndent: true
    )

    // MARK: - TeX

    static let tex = LanguageDefinition(
        keywords: [
            "begin", "end", "documentclass", "usepackage", "section", "subsection",
            "subsubsection", "chapter", "part", "paragraph", "item", "label", "ref", "cite",
            "includegraphics", "textbf", "textit", "emph", "footnote", "newcommand",
            "renewcommand", "def", "let", "if", "else", "fi", "input", "include",
            "bibliography", "maketitle", "tableofcontents",
        ],
        lineCommentPrefixes: ["%"],
        commandPrefix: "\\"
    )

    // MARK: - INI / 設定ファイル

    static let ini = LanguageDefinition(
        lineCommentPrefixes: ["//", ";"],
        stringDelimiters: ["\""]
    )
}

enum SyntaxHighlighter {
    /// 1行分をトークン化する。`startState`はこの行に入る時点での継続状態
    /// （ブロックコメント中／複数行文字列中／通常）。戻り値の`endState`は次の行に引き継ぐ。
    static func tokenize(
        line: String,
        startState: LineLexState,
        language: LanguageDefinition
    ) -> (tokens: [SyntaxToken], endState: LineLexState) {
        let chars = Array(line)

        // COBOL等: 行の特定列がマーカー文字なら行全体がコメント。
        if let col = language.fixedColumnCommentColumn, let markers = language.fixedColumnCommentMarkers,
           chars.count > col, markers.contains(chars[col]) {
            return ([SyntaxToken(range: 0..<chars.count, kind: .comment)], .normal)
        }

        var tokens: [SyntaxToken] = []
        var i = 0

        func matches(_ prefix: String, at index: Int) -> Bool {
            let prefixChars = Array(prefix)
            guard index + prefixChars.count <= chars.count else { return false }
            for k in 0..<prefixChars.count where chars[index + k] != prefixChars[k] { return false }
            return true
        }

        func stringKind(forDelimiter delimiter: String) -> SyntaxTokenKind {
            delimiter.first == "\"" ? .doubleQuoteString : .singleQuoteString
        }

        // 前の行から継続している状態を先に処理する。
        switch startState {
        case .normal:
            break
        case .blockComment(let pairIndex):
            let pair = language.blockComments[pairIndex]
            if let endIndex = findSequence(pair.end, in: chars, from: 0) {
                tokens.append(SyntaxToken(range: 0..<(endIndex + pair.end.count), kind: .comment))
                i = endIndex + pair.end.count
            } else {
                tokens.append(SyntaxToken(range: 0..<chars.count, kind: .comment))
                return (tokens, startState)
            }
        case .tripleQuoteString(let delimiter):
            let kind = stringKind(forDelimiter: delimiter)
            if let endIndex = findSequence(delimiter, in: chars, from: 0) {
                tokens.append(SyntaxToken(range: 0..<(endIndex + delimiter.count), kind: kind))
                i = endIndex + delimiter.count
            } else {
                tokens.append(SyntaxToken(range: 0..<chars.count, kind: kind))
                return (tokens, startState)
            }
        }

        while i < chars.count {
            let char = chars[i]

            if language.lineCommentPrefixes.contains(where: { matches($0, at: i) }) {
                tokens.append(SyntaxToken(range: i..<chars.count, kind: .comment))
                i = chars.count
                break
            }

            if let delimiter = language.tripleQuoteDelimiters.first(where: { matches($0, at: i) }) {
                let kind = stringKind(forDelimiter: delimiter)
                if let endIndex = findSequence(delimiter, in: chars, from: i + delimiter.count) {
                    tokens.append(SyntaxToken(range: i..<(endIndex + delimiter.count), kind: kind))
                    i = endIndex + delimiter.count
                } else {
                    tokens.append(SyntaxToken(range: i..<chars.count, kind: kind))
                    return (tokens, .tripleQuoteString(delimiter: delimiter))
                }
                continue
            }

            if let pairIndex = language.blockComments.firstIndex(where: { matches($0.start, at: i) }) {
                let pair = language.blockComments[pairIndex]
                if let endIndex = findSequence(pair.end, in: chars, from: i + pair.start.count) {
                    tokens.append(SyntaxToken(range: i..<(endIndex + pair.end.count), kind: .comment))
                    i = endIndex + pair.end.count
                } else {
                    tokens.append(SyntaxToken(range: i..<chars.count, kind: .comment))
                    return (tokens, .blockComment(pairIndex: pairIndex))
                }
                continue
            }

            if language.stringDelimiters.contains(char) {
                let quote = char
                var j = i + 1
                while j < chars.count {
                    if language.stringEscapeStyle == .backslash, chars[j] == "\\" {
                        j += 2
                        continue
                    }
                    if chars[j] == quote {
                        if language.stringEscapeStyle == .doubledQuote, j + 1 < chars.count, chars[j + 1] == quote {
                            j += 2
                            continue
                        }
                        j += 1
                        break
                    }
                    j += 1
                }
                let kind: SyntaxTokenKind = quote == "'" ? .singleQuoteString : .doubleQuoteString
                tokens.append(SyntaxToken(range: i..<min(j, chars.count), kind: kind))
                i = j
                continue
            }

            if char.isNumber {
                var j = i + 1
                while j < chars.count, chars[j].isNumber || chars[j] == "." || chars[j] == "x" || chars[j].isHexDigit {
                    j += 1
                }
                tokens.append(SyntaxToken(range: i..<j, kind: .number))
                i = j
                continue
            }

            if let prefix = language.commandPrefix, char == prefix {
                var j = i + 1
                while j < chars.count, chars[j].isLetter { j += 1 }
                if j > i + 1 {
                    tokens.append(SyntaxToken(range: i..<j, kind: .keyword))
                    i = j
                    continue
                }
            }

            if char.isLetter || char == "_" {
                var j = i + 1
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" || chars[j] == "-" {
                    j += 1
                }
                let word = String(chars[i..<j])
                let key = language.caseInsensitiveKeywords ? word.uppercased() : word
                let keywordSet = language.caseInsensitiveKeywords
                    ? Set(language.keywords.map { $0.uppercased() })
                    : language.keywords
                if keywordSet.contains(key) {
                    tokens.append(SyntaxToken(range: i..<j, kind: .keyword))
                }
                i = j
                continue
            }

            i += 1
        }

        return (tokens, .normal)
    }

    /// 言語判定に関係なく常に有効なURL自動検出（サクラエディタのCOLORIDX_URL相当）。
    static func urlRanges(in line: String) -> [Range<Int>] {
        let chars = Array(line)
        let prefixes = ["https://", "http://"]
        var ranges: [Range<Int>] = []
        var i = 0
        while i < chars.count {
            if let prefix = prefixes.first(where: { matchesPrefix($0, in: chars, at: i) }) {
                var j = i + prefix.count
                while j < chars.count, !chars[j].isWhitespace, !"\"'<>()[]{}　".contains(chars[j]) {
                    j += 1
                }
                ranges.append(i..<j)
                i = j
            } else {
                i += 1
            }
        }
        return ranges
    }

    private static func matchesPrefix(_ prefix: String, in chars: [Character], at index: Int) -> Bool {
        let p = Array(prefix)
        guard index + p.count <= chars.count else { return false }
        for k in 0..<p.count where chars[index + k] != p[k] { return false }
        return true
    }

    private static func findSequence(_ sequence: String, in chars: [Character], from start: Int) -> Int? {
        let seq = Array(sequence)
        guard !seq.isEmpty, start <= chars.count - seq.count else { return nil }
        var i = start
        while i <= chars.count - seq.count {
            var matched = true
            for k in 0..<seq.count where chars[i + k] != seq[k] {
                matched = false
                break
            }
            if matched { return i }
            i += 1
        }
        return nil
    }
}
