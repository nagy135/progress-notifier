import XCTest
@testable import ProgressCore

final class CloseTests: XCTestCase {
    func testClosePersistsWithoutBanningAndNextUpdateRestoresTheSameTask() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: "Build", progress: 25, etaSeconds: 60, description: "Started"))
        let item = try XCTUnwrap(registry.items.first)
        registry.close(id: item.id)
        XCTAssertTrue(registry.visibleItems.isEmpty)
        XCTAssertEqual(registry.items.map(\.id), [item.id])
        XCTAssertTrue(registry.deletions.isEmpty)
        XCTAssertFalse(registry.undoDeletion())

        let snapshot = try JSONDecoder().decode(ProgressSnapshot.self, from: JSONEncoder().encode(registry.snapshot))
        let restored = ProgressRegistry(snapshot: snapshot)
        XCTAssertTrue(restored.visibleItems.isEmpty)
        XCTAssertThrowsError(try restored.update(.init(name: "Build", progress: 101, etaSeconds: 0)))
        XCTAssertTrue(restored.visibleItems.isEmpty, "Rejected updates must not reopen closed tasks")
        try restored.update(.init(name: "Build", progress: 50, etaSeconds: 30, description: "Resumed"))
        XCTAssertEqual(restored.visibleItems.map(\.id), [item.id])
        XCTAssertEqual(restored.visibleItems.first?.progress, 50)
        XCTAssertEqual(restored.visibleItems.first?.createdAt, item.createdAt)
        XCTAssertEqual(restored.visibleItems.first?.updates.map(\.description), ["Resumed", "Started"])
        XCTAssertTrue(restored.snapshot.closedItemIDs?.isEmpty == true)
    }

    func testCompletionAfterCloseStillCompletesAndCanBeClosedAndRecalled() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: "Build", progress: 25, etaSeconds: 60))
        let id = try XCTUnwrap(registry.items.first?.id)
        registry.close(id: id)
        XCTAssertTrue(try registry.update(.init(name: "Build", progress: 100, etaSeconds: 0)))
        XCTAssertEqual(registry.revealedHistory.map(\.id), [id])
        registry.close(id: id)
        registry.removeCompleted(id: id) // Delayed feedback callback cannot reopen it.
        XCTAssertTrue(registry.items.isEmpty)
        XCTAssertTrue(registry.revealedHistory.isEmpty)
        XCTAssertEqual(registry.history.map(\.id), [id])
        XCTAssertTrue(registry.revealNextCompleted())
        XCTAssertEqual(registry.revealedHistory.map(\.id), [id])
        registry.close(id: id)
        try registry.update(.init(name: "Build", progress: 5, etaSeconds: 60))
        XCTAssertEqual(registry.visibleItems.first?.progress, 5)
        XCTAssertNotEqual(registry.visibleItems.first?.id, id)
        XCTAssertTrue(registry.deletions.isEmpty)
    }

    func testCloseDoesNotAffectBansOrTheirUndoStack() throws {
        let registry = ProgressRegistry()
        for name in ["Deleted", "Closed"] {
            try registry.update(.init(name: name, progress: 25, etaSeconds: 60))
        }
        let closedID = registry.items[1].id
        registry.dismiss(name: "Deleted")
        registry.close(id: closedID)
        registry.clearCompleted()
        try registry.update(.init(name: "Deleted", progress: 50, etaSeconds: 30))
        XCTAssertTrue(registry.visibleItems.isEmpty)
        XCTAssertEqual(registry.deletions.map(\.item.name), ["Deleted"])
        XCTAssertTrue(registry.undoDeletion())
        XCTAssertEqual(registry.visibleItems.map(\.name), ["Deleted"])
        // Explicit deletion of an already closed task still bans it and undo shows it.
        registry.dismiss(id: closedID)
        XCTAssertTrue(registry.undoDeletion())
        XCTAssertEqual(registry.visibleItems.map(\.id).last, closedID)
    }
}
