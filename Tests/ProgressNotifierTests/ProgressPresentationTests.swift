import AppKit
import XCTest
import ProgressCore
@testable import ProgressNotifier

final class ProgressPresentationTests: XCTestCase {
    private func item(_ name: String) throws -> ProgressItem {
        let registry = ProgressRegistry()
        try registry.update(ProgressUpdate(name: name, progress: 50, etaSeconds: 60))
        return try XCTUnwrap(registry.items.first)
    }

    private func settle(_ presentation: ProgressPresentation, action: () -> Void) -> [CGFloat] {
        let complete = expectation(description: "Transition settles")
        var heights: [CGFloat] = []
        presentation.geometryChanged = {
            heights.append(presentation.windowHeight)
            // Leave the completion condition to the clock so intermediate samples are retained.
        }
        action()
        DispatchQueue.main.asyncAfter(deadline: .now() + ProgressPresentation.transitionDuration + 0.08) {
            complete.fulfill()
        }
        wait(for: [complete], timeout: 2)
        presentation.geometryChanged = nil
        return heights
    }

    func testMeasuredRowsGrowWithoutScrolling() throws {
        let presentation = ProgressPresentation(compact: false)
        let first = try item("First")
        let second = try item("Second")
        presentation.update(items: [first], compact: false, animated: false)
        presentation.measure([first.id: 50], animated: false)
        let start = presentation.windowHeight
        presentation.update(items: [first, second], compact: false, animated: true)
        // A new card takes no space until its text has been measured.
        XCTAssertEqual(presentation.windowHeight, start)
        let heights = settle(presentation) {
            presentation.measure([first.id: 50, second.id: 68], animated: true)
        }
        XCTAssertEqual(presentation.windowHeight, 80 + 92 + 110 + 6 + 8)
        XCTAssertTrue(zip(heights, heights.dropFirst()).allSatisfy { $0 <= $1 })
        XCTAssertFalse(presentation.needsScrolling)
    }

    func testRecallFromEmptyDoesNotBulgeBetweenEqualHeightStates() throws {
        let presentation = ProgressPresentation(compact: false)
        let recalled = try item("Recalled")
        let start = presentation.windowHeight
        presentation.update(items: [recalled], compact: false, animated: true)
        // A 50-point detail block makes the card exactly as tall as the empty state.
        let heights = settle(presentation) {
            presentation.measure([recalled.id: 50], animated: true)
        }
        XCTAssertEqual(presentation.windowHeight, start)
        XCTAssertTrue(heights.allSatisfy { abs($0 - start) < 0.001 },
                      "Recall must not briefly grow and shrink when both states have the same height: \(heights)")
    }

    func testClearingTwoCardsShrinksWithoutCompressingTheirContents() throws {
        let presentation = ProgressPresentation(compact: false)
        let items = try [item("First"), item("Second")]
        presentation.update(items: items, compact: false, animated: false)
        presentation.measure(Dictionary(uniqueKeysWithValues: items.map { ($0.id, CGFloat(60)) }), animated: false)
        let start = presentation.windowHeight
        var keptDepartingRows = false
        let heights = settle(presentation) {
            presentation.update(items: [], compact: false, animated: true)
            keptDepartingRows = presentation.rows.count == 2 && presentation.windowHeight == start
        }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { XCTAssertTrue(keptDepartingRows) }
        XCTAssertTrue(zip(heights, heights.dropFirst()).allSatisfy { $0 >= $1 })
        XCTAssertEqual(presentation.windowHeight, 180)
        XCTAssertTrue(presentation.rows.isEmpty)
        XCTAssertEqual(presentation.emptyPresence, 1)
    }

    func testScrollingStartsOnlyWhenTheScreenLimitIsReached() throws {
        let presentation = ProgressPresentation(compact: false)
        presentation.maximumHeight = 300
        let items = try (0..<8).map { try item("Task \($0)") }
        presentation.update(items: Array(items.prefix(1)), compact: false, animated: false)
        presentation.measure([items[0].id: 60], animated: false)
        XCTAssertFalse(presentation.needsScrolling)
        var overflowFrames = 0
        presentation.update(items: items, compact: false, animated: true)
        let complete = expectation(description: "Overflow settles")
        presentation.geometryChanged = {
            XCTAssertLessThanOrEqual(presentation.windowHeight, 300)
            if presentation.needsScrolling {
                overflowFrames += 1
                XCTAssertEqual(presentation.windowHeight, 300)
            }
        }
        presentation.measure(Dictionary(uniqueKeysWithValues: items.map { ($0.id, CGFloat(60)) }), animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { complete.fulfill() }
        wait(for: [complete], timeout: 2)
        XCTAssertGreaterThan(overflowFrames, 0)
        XCTAssertTrue(presentation.needsScrolling)
        presentation.update(items: [items[0]], compact: false, animated: false)
        XCTAssertFalse(presentation.needsScrolling)
    }

    func testNewActiveRowsStayAheadOfRecalledHistory() throws {
        let presentation = ProgressPresentation(compact: false)
        let history = try item("History")
        let active = try item("Active")
        presentation.update(items: [history], compact: false, animated: false)
        presentation.update(items: [active, history], compact: false, animated: false)
        XCTAssertEqual(presentation.rows.map(\.id), [active.id, history.id])
    }

    func testReversingRecallAndClearKeepsTheCurrentGeometry() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let presentation = ProgressPresentation(compact: false)
        let items = try [item("First"), item("Second")]
        presentation.update(items: items, compact: false, animated: false)
        presentation.measure(Dictionary(uniqueKeysWithValues: items.map { ($0.id, CGFloat(60)) }), animated: false)
        let reverse = expectation(description: "Reverse partway through clear")
        presentation.update(items: [], compact: false, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let before = presentation.windowHeight
            XCTAssertTrue(presentation.rows.allSatisfy { $0.presence > 0 && $0.presence < 1 })
            XCTAssertTrue(presentation.rows.allSatisfy { $0.detailsHeight == 60 })
            presentation.update(items: items, compact: true, animated: true)
            XCTAssertEqual(presentation.windowHeight, before)
            reverse.fulfill()
        }
        wait(for: [reverse], timeout: 2)
        _ = settle(presentation) {}
        XCTAssertEqual(presentation.windowHeight, 36 + 20 + 20 + 2)
        XCTAssertEqual(presentation.rows.count, 2)
        XCTAssertEqual(presentation.expansion, 0)
    }
}
