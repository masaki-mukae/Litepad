import AppKit
import CoreText

/// 描画まわり: 行の属性文字列構築、`draw(_:)`本体、ガター（行番号・ブックマーク）、
/// 選択範囲・対括弧のハイライト、キャレット。
extension TextCanvasView {
    var textAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraphStyle]
    }

    private func color(for kind: SyntaxTokenKind) -> NSColor {
        switch kind {
        case .keyword: return .systemPurple
        case .singleQuoteString: return .systemRed
        case .doubleQuoteString: return .systemPink
        case .comment: return .systemGreen
        case .number: return .systemOrange
        case .url: return .systemBlue
        }
    }

    var composingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: NSColor.textColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .backgroundColor: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35),
            .paragraphStyle: paragraphStyle,
        ]
    }

    private func highlightedLineString(_ lineText: String, lineIdx: Int) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: lineText, attributes: textAttributes)
        let chars = Array(lineText)

        func apply(_ kind: SyntaxTokenKind, _ range: Range<Int>) {
            let nsRange = NSRange(location: range.lowerBound, length: range.upperBound - range.lowerBound)
            guard nsRange.location >= 0, nsRange.location + nsRange.length <= chars.count else { return }
            result.addAttribute(.foregroundColor, value: color(for: kind), range: nsRange)
        }

        if let language = currentLanguage {
            let startState = syntaxCache.state(atStartOf: lineIdx, buffer: buffer, language: language)
            let (tokens, _) = SyntaxHighlighter.tokenize(line: lineText, startState: startState, language: language)
            for token in tokens { apply(token.kind, token.range) }
        }

        // 言語判定に関係なく、URLは常に検出して色を付ける（サクラエディタのCOLORIDX_URL相当）。
        for range in SyntaxHighlighter.urlRanges(in: lineText) { apply(.url, range) }

        return result
    }

    func attributedString(forLine lineIdx: Int) -> NSAttributedString {
        let lineText = buffer.line(at: lineIdx)
        let result = highlightedLineString(lineText, lineIdx: lineIdx)
        guard lineIdx == composingLine, !composingText.isEmpty else {
            return result
        }
        let col = min(cursor.column, Array(lineText).count)
        result.insert(NSAttributedString(string: composingText, attributes: composingAttributes), at: col)
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        guard buffer.lineCount > 0, lineHeight > 0 else { return }
        let firstLine = max(0, Int(dirtyRect.minY / lineHeight))
        let lastLine = min(buffer.lineCount - 1, Int(ceil(dirtyRect.maxY / lineHeight)))
        guard firstLine <= lastLine else { return }

        let selection = normalizedSelection
        let rectSelection = normalizedRectSelection
        let bracketMatch = hasSelection ? nil : BracketMatcher.matchingPositions(in: buffer, cursor: cursor)
        var widestVisibleLine: CGFloat = 0

        let startX = textStartX
        for lineIdx in firstLine...lastLine {
            let ctLine = CTLineCreateWithAttributedString(attributedString(forLine: lineIdx))
            widestVisibleLine = max(widestVisibleLine, CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil)) + startX + textInset)
            let lineTop = CGFloat(lineIdx) * lineHeight + topInset

            if let rectSelection, lineIdx >= rectSelection.topLine, lineIdx <= rectSelection.bottomLine {
                let lineLength = buffer.line(at: lineIdx).count
                let startCol = min(rectSelection.leftColumn, lineLength)
                let endCol = min(rectSelection.rightColumn, lineLength)
                if endCol > startCol {
                    drawHighlightRect(for: ctLine, lineTop: lineTop, startCol: startCol, endCol: endCol)
                }
            } else if let selection, lineIdx >= selection.start.line, lineIdx <= selection.end.line {
                drawSelectionHighlight(for: ctLine, lineIdx: lineIdx, lineTop: lineTop, selection: selection)
            }

            if let bracketMatch {
                let bracketColor = NSColor.systemBlue.withAlphaComponent(0.25)
                if lineIdx == bracketMatch.0.line {
                    drawHighlightRect(for: ctLine, lineTop: lineTop, startCol: bracketMatch.0.column, endCol: bracketMatch.0.column + 1, color: bracketColor)
                }
                if lineIdx == bracketMatch.1.line {
                    drawHighlightRect(for: ctLine, lineTop: lineTop, startCol: bracketMatch.1.column, endCol: bracketMatch.1.column + 1, color: bracketColor)
                }
            }

            // NSViewはisFlipped=trueで上原点だが、CoreTextは下原点前提のため
            // 行ごとにローカルでY軸を反転してから描画する。
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: startX, y: lineTop + baselineOffset)
            context.scaleBy(x: 1, y: -1)
            CTLineDraw(ctLine, context)
            context.restoreGState()
        }

        if AppSettings.shared.showLineNumbers {
            drawGutter(firstLine: firstLine, lastLine: lastLine, dirtyRect: dirtyRect, context: context)
        }

        drawCaret(in: context)
        growFrameWidthIfNeeded(to: widestVisibleLine)
    }

    /// 行番号ガター（背景・各行の行番号・ブックマークの目印）を描画する。
    /// 行番号は`NSString.draw(at:)`ではなく本文と同じ`CTLineDraw`＋座標反転で描く。
    /// 前者はフォントのバウンディングボックス基準、本文は`baselineOffset`で決めた
    /// ベースライン基準と異なる縦位置の取り方をするため、混在させると行番号と本文の
    /// ベースラインがずれて見えてしまう。
    private func drawGutter(firstLine: Int, lastLine: Int, dirtyRect: NSRect, context: CGContext) {
        let width = gutterWidth
        NSColor.controlBackgroundColor.setFill()
        NSRect(x: 0, y: dirtyRect.minY, width: width, height: dirtyRect.height).fill()

        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let bookmarkColor = NSColor.systemYellow

        for lineIdx in firstLine...lastLine {
            let lineTop = CGFloat(lineIdx) * lineHeight + topInset

            if bookmarkStore.contains(lineIdx) {
                bookmarkColor.setFill()
                NSRect(x: 0, y: lineTop, width: 3, height: lineHeight).fill()
            }

            let ctLine = CTLineCreateWithAttributedString(
                NSAttributedString(string: String(lineIdx + 1), attributes: numberAttributes)
            )
            let numberWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
            let x = width - gutterPadding - numberWidth

            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: x, y: lineTop + baselineOffset)
            context.scaleBy(x: 1, y: -1)
            CTLineDraw(ctLine, context)
            context.restoreGState()
        }
    }

    private func drawSelectionHighlight(
        for ctLine: CTLine,
        lineIdx: Int,
        lineTop: CGFloat,
        selection: (start: CursorPosition, end: CursorPosition)
    ) {
        let lineLength = buffer.line(at: lineIdx).count
        let startCol = lineIdx == selection.start.line ? selection.start.column : 0
        let endCol = lineIdx == selection.end.line ? selection.end.column : lineLength
        guard endCol > startCol || lineIdx < selection.end.line else { return }

        let startX = CTLineGetOffsetForStringIndex(ctLine, startCol, nil)
        // 選択範囲が行末を越えて次行に続く場合は、改行文字も選択中であることが視認できるよう幅を足す。
        let endX: CGFloat = (endCol == lineLength && lineIdx < selection.end.line)
            ? CTLineGetOffsetForStringIndex(ctLine, endCol, nil) + 8
            : CTLineGetOffsetForStringIndex(ctLine, endCol, nil)

        drawHighlightRect(startX: startX, endX: endX, lineTop: lineTop)
    }

    /// 矩形選択のハイライト（行末を越えて伸ばす処理はしない、純粋な列範囲）。
    private func drawHighlightRect(for ctLine: CTLine, lineTop: CGFloat, startCol: Int, endCol: Int, color: NSColor = .selectedTextBackgroundColor) {
        let startX = CTLineGetOffsetForStringIndex(ctLine, startCol, nil)
        let endX = CTLineGetOffsetForStringIndex(ctLine, endCol, nil)
        drawHighlightRect(startX: startX, endX: endX, lineTop: lineTop, color: color)
    }

    private func drawHighlightRect(startX: CGFloat, endX: CGFloat, lineTop: CGFloat, color: NSColor = .selectedTextBackgroundColor) {
        let rect = NSRect(x: textStartX + startX, y: lineTop, width: max(1, endX - startX), height: lineHeight)
        color.setFill()
        rect.fill()
    }

    func caretRect() -> NSRect {
        guard cursor.line < buffer.lineCount else { return .zero }
        let ctLine = CTLineCreateWithAttributedString(attributedString(forLine: cursor.line))
        let caretCol = cursor.column + (cursor.line == composingLine ? composingText.count : 0)
        let xOffset = CTLineGetOffsetForStringIndex(ctLine, caretCol, nil)
        let y = CGFloat(cursor.line) * lineHeight + topInset
        return NSRect(x: textStartX + xOffset - 1, y: y, width: 2, height: lineHeight)
    }

    private func drawCaret(in context: CGContext) {
        guard isCaretVisible, window?.firstResponder === self else { return }
        NSColor.controlAccentColor.setFill()
        caretRect().fill()
    }
}
