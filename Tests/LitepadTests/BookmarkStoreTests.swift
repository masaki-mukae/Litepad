import XCTest
@testable import Litepad

final class BookmarkStoreTests: XCTestCase {
    func testToggleAddsAndRemoves() {
        let store = BookmarkStore()
        XCTAssertFalse(store.contains(3))
        store.toggle(3)
        XCTAssertTrue(store.contains(3))
        store.toggle(3)
        XCTAssertFalse(store.contains(3))
    }

    func testNextLineWrapsAround() {
        let store = BookmarkStore()
        store.toggle(2)
        store.toggle(5)
        store.toggle(9)

        XCTAssertEqual(store.nextLine(after: 0), 2)
        XCTAssertEqual(store.nextLine(after: 2), 5)
        XCTAssertEqual(store.nextLine(after: 5), 9)
        XCTAssertEqual(store.nextLine(after: 9), 2, "最後を超えたら先頭へ巡回する")
    }

    func testPreviousLineWrapsAround() {
        let store = BookmarkStore()
        store.toggle(2)
        store.toggle(5)
        store.toggle(9)

        XCTAssertEqual(store.previousLine(before: 100), 9)
        XCTAssertEqual(store.previousLine(before: 9), 5)
        XCTAssertEqual(store.previousLine(before: 5), 2)
        XCTAssertEqual(store.previousLine(before: 2), 9, "先頭より前は末尾へ巡回する")
    }

    func testNextAndPreviousReturnNilWhenEmpty() {
        let store = BookmarkStore()
        XCTAssertNil(store.nextLine(after: 0))
        XCTAssertNil(store.previousLine(before: 0))
    }

    // MARK: - 編集による追従

    func testAdjustShiftsBookmarksAfterInsertedLines() {
        let store = BookmarkStore()
        store.toggle(10)
        // 行3で2行分(lineDelta=2)増える編集
        store.adjust(
            editStart: CursorPosition(line: 3, column: 0),
            oldEnd: CursorPosition(line: 3, column: 0),
            newEnd: CursorPosition(line: 5, column: 0)
        )
        XCTAssertTrue(store.contains(12), "編集より後ろのブックマークは行数ぶんずれる")
        XCTAssertFalse(store.contains(10))
    }

    func testAdjustLeavesBookmarksBeforeEditUntouched() {
        let store = BookmarkStore()
        store.toggle(1)
        store.adjust(
            editStart: CursorPosition(line: 10, column: 0),
            oldEnd: CursorPosition(line: 10, column: 0),
            newEnd: CursorPosition(line: 12, column: 0)
        )
        XCTAssertTrue(store.contains(1), "編集より前のブックマークは影響を受けない")
    }

    func testAdjustDropsBookmarksInsideDeletedRange() {
        let store = BookmarkStore()
        store.toggle(5) // 削除範囲の内側
        store.toggle(20) // 削除範囲の後ろ
        // 行3〜行10を削除(lineDelta = -7)
        store.adjust(
            editStart: CursorPosition(line: 3, column: 0),
            oldEnd: CursorPosition(line: 10, column: 0),
            newEnd: CursorPosition(line: 3, column: 0)
        )
        XCTAssertFalse(store.contains(5), "削除範囲に飲み込まれた行のブックマークは消える")
        XCTAssertTrue(store.contains(13), "削除範囲より後ろは行数ぶん繰り上がる")
    }

    func testAdjustDoesNothingWhenLineCountUnchanged() {
        let store = BookmarkStore()
        store.toggle(5)
        store.adjust(
            editStart: CursorPosition(line: 5, column: 0),
            oldEnd: CursorPosition(line: 5, column: 3),
            newEnd: CursorPosition(line: 5, column: 5)
        )
        XCTAssertTrue(store.contains(5), "行内だけの編集ではブックマークは動かない")
    }
}
