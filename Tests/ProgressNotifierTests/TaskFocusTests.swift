import XCTest
import ProgressCore
@testable import ProgressNotifier

final class TaskFocusTests: XCTestCase {
    private func items() throws -> [ProgressItem] {
        let registry = ProgressRegistry()
        for name in ["First", "Second", "Third"] {
            try registry.update(.init(name: name, progress: 25, etaSeconds: 60, description: "Started \(name)"))
            try registry.update(.init(name: name, progress: 75, etaSeconds: 20, description: "Tested \(name)"))
        }
        return registry.items
    }

    func testNavigationStartsAtFirstAndStopsAtListBoundaries() throws {
        let items = try items()
        let presentation = ProgressPresentation(compact: false)
        presentation.update(items: items, compact: false, animated: false)
        XCTAssertEqual(presentation.focusedItemID, items[0].id)
        presentation.moveFocus(by: -1, animated: false)
        XCTAssertEqual(presentation.focusedItemID, items[0].id)
        presentation.moveFocus(by: 1, animated: false)
        XCTAssertEqual(presentation.focusedItemID, items[1].id)
        presentation.moveFocus(by: 1, animated: false)
        presentation.moveFocus(by: 1, animated: false)
        XCTAssertEqual(presentation.focusedItemID, items[2].id)
        presentation.moveFocus(by: -1, animated: false)
        XCTAssertEqual(presentation.focusedItemID, items[1].id)
    }

    func testProgressUpdatesAndNewTasksDoNotStealSelection() throws {
        var items = try items()
        let presentation = ProgressPresentation(compact: false)
        presentation.update(items: items, compact: false, animated: false)
        presentation.moveFocus(by: 1, animated: false)
        let selected = items[1].id
        items[1].progress = 80
        presentation.update(items: items, compact: false, animated: false)
        XCTAssertEqual(presentation.focusedItemID, selected)
        XCTAssertEqual(presentation.focusedItem?.progress, 80)
        presentation.update(items: [items[2], items[0], items[1]], compact: false, animated: false)
        XCTAssertEqual(presentation.focusedItemID, selected)
    }

    func testRemovingFocusedTaskSelectsNextThenPreviousAndHandlesEmptyList() throws {
        let items = try items()
        let presentation = ProgressPresentation(compact: false)
        presentation.update(items: items, compact: false, animated: false)
        presentation.moveFocus(by: 1, animated: false)
        presentation.setShowsUpdates(true, animated: false)
        presentation.update(items: [items[0], items[2]], compact: false, animated: false)
        XCTAssertEqual(presentation.focusedItemID, items[2].id)
        presentation.update(items: [items[0]], compact: false, animated: false)
        XCTAssertEqual(presentation.focusedItemID, items[0].id)
        presentation.update(items: [], compact: false, animated: false)
        presentation.moveFocus(by: 1, animated: false)
        presentation.setShowsUpdates(true, animated: false)
        XCTAssertNil(presentation.focusedItemID)
        XCTAssertFalse(presentation.showsUpdates)
        presentation.update(items: items, compact: false, animated: false)
        XCTAssertEqual(presentation.focusedItemID, items[0].id)
        XCTAssertFalse(presentation.showsUpdates)
    }

    func testOpenLedgerFollowsFocusAndLeavesOtherTasksFolded() throws {
        let items = try items()
        let presentation = ProgressPresentation(compact: false)
        presentation.update(items: items, compact: false, animated: false)
        presentation.measureHistory(Dictionary(uniqueKeysWithValues: items.map { ($0.id, CGFloat(80)) }), animated: false)
        presentation.setShowsUpdates(true, animated: false)
        XCTAssertEqual(presentation.rows.map(\.historyHeight), [80, 0, 0])
        presentation.moveFocus(by: 1, animated: false)
        XCTAssertEqual(presentation.rows.map(\.historyHeight), [0, 80, 0])
        presentation.setShowsUpdates(false, animated: false)
        XCTAssertEqual(presentation.rows.map(\.historyHeight), [0, 0, 0])
        presentation.moveFocus(by: 1, animated: false)
        XCTAssertEqual(presentation.rows.map(\.historyHeight), [0, 0, 0])
        presentation.setShowsUpdates(true, animated: false)
        XCTAssertEqual(presentation.rows.map(\.historyHeight), [0, 0, 80])
    }

    func testTaskWithoutNotesDoesNotOpenAnotherTasksHistory() throws {
        var items = try items()
        items[1].updates = []
        let presentation = ProgressPresentation(compact: true)
        presentation.update(items: items, compact: true, animated: false)
        presentation.measureHistory([items[0].id: 80, items[1].id: 0, items[2].id: 80], animated: false)
        presentation.setShowsUpdates(true, animated: false)
        presentation.moveFocus(by: 1, animated: false)
        XCTAssertEqual(presentation.rows.map(\.historyHeight), [0, 0, 0])
        presentation.update(items: items, compact: false, animated: false)
        XCTAssertEqual(presentation.focusedItemID, items[1].id)
        XCTAssertEqual(presentation.rows.map(\.historyHeight), [0, 0, 0])
    }
}
