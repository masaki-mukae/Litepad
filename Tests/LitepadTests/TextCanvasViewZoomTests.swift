import XCTest
import AppKit
@testable import Litepad

/// `TextCanvasView`の表示倍率機能（⌘+スクロール／トラックパッドのピンチで変更する、
/// サクラエディタの「文字表示倍率」相当）を検証する。
final class TextCanvasViewZoomTests: XCTestCase {
    func testAdjustZoomScalesFontSize() {
        let view = TextCanvasView(buffer: DocumentBuffer(text: "hello"))
        let baseSize = view.font.pointSize

        view.adjustZoom(by: 2.0)
        XCTAssertEqual(view.font.pointSize, baseSize * 2, accuracy: 0.01)

        view.adjustZoom(by: 0.5)
        XCTAssertEqual(view.font.pointSize, baseSize, accuracy: 0.01, "2倍してから半分に戻せば元のサイズに戻るはず")
    }

    func testZoomClampsToMaximum() {
        let view = TextCanvasView(buffer: DocumentBuffer(text: "hello"))
        let baseSize = view.font.pointSize

        for _ in 0..<10 { view.adjustZoom(by: 2.0) }
        XCTAssertEqual(view.font.pointSize, baseSize * 4, accuracy: 0.01, "上限400%でクランプされるはず")
    }

    func testZoomClampsToMinimum() {
        let view = TextCanvasView(buffer: DocumentBuffer(text: "hello"))
        let baseSize = view.font.pointSize

        for _ in 0..<10 { view.adjustZoom(by: 0.5) }
        XCTAssertEqual(view.font.pointSize, baseSize * 0.25, accuracy: 0.01, "下限25%でクランプされるはず")
    }

    func testLineHeightAndGutterScaleWithZoom() {
        let view = TextCanvasView(buffer: DocumentBuffer(text: "hello"))
        let baseLineHeight = view.lineHeight
        let baseGutterWidth = view.gutterWidth

        view.adjustZoom(by: 2.0)
        XCTAssertGreaterThan(view.lineHeight, baseLineHeight, "行の高さも拡大に追従するはず")
        XCTAssertGreaterThan(view.gutterWidth, baseGutterWidth, "行番号ガターの幅も拡大に追従するはず")
    }

    func testNoOpFactorDoesNotChangeFont() {
        let view = TextCanvasView(buffer: DocumentBuffer(text: "hello"))
        let baseSize = view.font.pointSize

        view.adjustZoom(by: 1.0)
        XCTAssertEqual(view.font.pointSize, baseSize, accuracy: 0.01)
    }
}
