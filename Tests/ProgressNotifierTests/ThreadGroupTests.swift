import XCTest
import ProgressCore
@testable import ProgressNotifier

final class ThreadGroupTests: XCTestCase {
    private func item(_ name: String, thread: String? = nil, environment: String = "mac") throws -> ProgressItem {
        let registry = ProgressRegistry()
        try registry.update(.init(name: name, progress: 25, etaSeconds: 60, project: "Same project",
                                  t3Thread: thread.map { .init(environmentId: environment, threadId: $0) }))
        return try XCTUnwrap(registry.items.first)
    }

    func testOnlySharedDestinationsReceiveSymbolsInBothModes() throws {
        let items = try [item("First", thread: "shared"), item("Second", thread: "shared"),
                         item("Third", thread: "shared"), item("Other environment", thread: "shared", environment: "remote"),
                         item("Other thread", thread: "unique"), item("Unlinked"), item("Also unlinked")]
        for compact in [false, true] {
            let presentation = ProgressPresentation(compact: compact)
            presentation.update(items: items, compact: compact, animated: false)
            XCTAssertEqual(presentation.rows.map(\.threadGroupSymbol), [.circle, .circle, .circle, nil, nil, nil, nil])
        }
    }

    func testFourGroupsKeepDistinctSymbolsAcrossReorderingAndModeChanges() throws {
        let groups = try (0..<5).map { group in
            try (0..<2).map { try item("\(group)-\($0)", thread: "thread:\(group)") }
        }
        let presentation = ProgressPresentation(compact: false)
        let items = groups.flatMap { $0 }
        presentation.update(items: items, compact: false, animated: false)
        let symbols: [ThreadGroupSymbol?] = [.circle, .triangle, .square, .diamond, nil]
        XCTAssertEqual(presentation.rows.map(\.threadGroupSymbol), symbols.flatMap { [$0, $0] })
        let original = Dictionary(uniqueKeysWithValues: presentation.rows.map { ($0.id, $0.threadGroupSymbol) })
        var reordered = Array(items.reversed())
        reordered[0].progress = 80
        presentation.update(items: reordered, compact: true, animated: false)
        for row in presentation.rows {
            XCTAssertEqual(row.threadGroupSymbol, original[row.id] ?? nil)
        }
        // A single remaining task no longer marks a group; the fifth group can use its slot.
        presentation.update(items: Array(items.dropFirst()), compact: true, animated: false)
        XCTAssertNil(presentation.rows[0].threadGroupSymbol)
        XCTAssertEqual(presentation.rows.suffix(2).map(\.threadGroupSymbol), [.circle, .circle])
        XCTAssertEqual(presentation.rows[1].threadGroupSymbol, .triangle)
        presentation.update(items: [], compact: true, animated: false)
        presentation.update(items: groups[4], compact: false, animated: false)
        XCTAssertEqual(presentation.rows.map(\.threadGroupSymbol), [.circle, .circle])
    }

    func testSymbolsFollowChangedThreadMetadataAndVisibleCompletedHistory() throws {
        var first = try item("First", thread: "shared")
        var second = try item("Second", thread: "other")
        let presentation = ProgressPresentation(compact: false)
        presentation.update(items: [first, second], compact: false, animated: false)
        XCTAssertTrue(presentation.rows.allSatisfy { $0.threadGroupSymbol == nil })
        second.t3Thread = first.t3Thread
        first.completing = true
        presentation.update(items: [second, first], compact: false, animated: false)
        XCTAssertEqual(presentation.rows.map(\.threadGroupSymbol), [.circle, .circle])
        // Clearing history removes its membership; recalling it restores the match.
        presentation.update(items: [second], compact: false, animated: false)
        XCTAssertNil(presentation.rows[0].threadGroupSymbol)
        presentation.update(items: [second, first], compact: true, animated: false)
        XCTAssertEqual(presentation.rows.map(\.threadGroupSymbol), [.circle, .circle])
    }
}
