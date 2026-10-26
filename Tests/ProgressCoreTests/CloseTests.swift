import XCTest
@testable import ProgressCore

final class CloseTests: XCTestCase {
    func testCloseAndBanStacksUndoIndependentlyInLIFOOrderAcrossRelaunch() throws {
        let registry = ProgressRegistry()
        for name in ["First", "Banned", "Last"] {
            try registry.update(.init(name: name, progress: 25, etaSeconds: 60, description: "Started"))
        }
        let ids = registry.items.map(\.id)
        registry.close(id: ids[0])
        registry.dismiss(id: ids[1])
        registry.close(id: ids[2])
        registry.close(id: ids[2]) // Closing twice must not create another entry.
        let snapshot = try JSONDecoder().decode(ProgressSnapshot.self, from: JSONEncoder().encode(registry.snapshot))
        let restored = ProgressRegistry(snapshot: snapshot)
        XCTAssertTrue(restored.visibleItems.isEmpty)
        XCTAssertEqual(restored.undoClose()?.id, ids[2])
        XCTAssertEqual(restored.deletions.map(\.item.id), [ids[1]])
        try restored.update(.init(name: "Banned", progress: 75, etaSeconds: 0))
        XCTAssertEqual(restored.visibleItems.map(\.id), [ids[2]])
        XCTAssertTrue(restored.undoDeletion())
        XCTAssertEqual(restored.closures.map(\.item.id), [ids[0]])
        XCTAssertEqual(restored.undoClose()?.id, ids[0])
        XCTAssertEqual(restored.visibleItems.map(\.id), ids)
        XCTAssertEqual(restored.visibleItems[1].progress, 25)
        XCTAssertNil(restored.undoClose())
        XCTAssertFalse(restored.undoDeletion())
    }

    func testUpdatesAndRecallRemoveAlreadyReopenedCardsFromCloseStack() throws {
        let registry = ProgressRegistry()
        for name in ["First", "Last"] {
            try registry.update(.init(name: name, progress: 25, etaSeconds: 60))
        }
        let ids = registry.items.map(\.id)
        registry.close(id: ids[0])
        registry.close(id: ids[1])
        try registry.update(.init(name: "Last", progress: 50, etaSeconds: 30))
        XCTAssertEqual(registry.closures.map(\.item.id), [ids[0]])
        XCTAssertEqual(registry.undoClose()?.id, ids[0], "Skip the task its update already reopened")
        XCTAssertNil(registry.undoClose())
        registry.close(id: ids[0])
        try registry.update(.init(name: "First", progress: 100, etaSeconds: 0))
        XCTAssertTrue(registry.closures.isEmpty)
        registry.close(id: ids[0])
        XCTAssertEqual(registry.undoClose()?.id, ids[0])
        registry.removeCompleted(id: ids[0])
        XCTAssertEqual(registry.revealedHistory.map(\.id), [ids[0]])
        registry.close(id: ids[0])
        XCTAssertTrue(registry.revealNextCompleted())
        XCTAssertTrue(registry.closures.isEmpty)
        XCTAssertNil(registry.undoClose())
    }

    func testBanningClosedTaskCannotBeUndoneByCloseUndo() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: "Build", progress: 25, etaSeconds: 60))
        let id = try XCTUnwrap(registry.items.first?.id)
        registry.close(id: id)
        registry.dismiss(name: "Build")
        XCTAssertNil(registry.undoClose())
        try registry.update(.init(name: "Build", progress: 50, etaSeconds: 30))
        XCTAssertTrue(registry.visibleItems.isEmpty)
        XCTAssertTrue(registry.undoDeletion())
        XCTAssertEqual(registry.visibleItems.map(\.id), [id])
        XCTAssertNil(registry.undoClose())
    }

    func testUndoClosedCompletionSurvivesHistoryTrimmingAndANewRunWithSameName() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: "Build", progress: 25, etaSeconds: 60))
        try registry.update(.init(name: "Build", progress: 100, etaSeconds: 0))
        let id = try XCTUnwrap(registry.items.first?.id)
        registry.close(id: id)
        registry.removeCompleted(id: id)
        for index in 0..<ProgressRegistry.historyLimit {
            let name = "Done \(index)"
            try registry.update(.init(name: name, progress: 25, etaSeconds: 60))
            try registry.update(.init(name: name, progress: 100, etaSeconds: 0))
            registry.removeCompleted(id: try XCTUnwrap(registry.items.first?.id))
        }
        XCTAssertFalse(registry.history.contains(where: { $0.id == id }))
        try registry.update(.init(name: "Build", progress: 10, etaSeconds: 60))
        let activeID = try XCTUnwrap(registry.items.first?.id)
        let snapshot = try JSONDecoder().decode(ProgressSnapshot.self, from: JSONEncoder().encode(registry.snapshot))
        let restored = ProgressRegistry(snapshot: snapshot)
        restored.clearCompleted()
        XCTAssertEqual(restored.undoClose()?.id, id)
        XCTAssertEqual(restored.revealedHistory.map(\.id), [id])
        XCTAssertEqual(restored.visibleItems.map(\.id), [activeID])
        XCTAssertEqual(restored.history.count, ProgressRegistry.historyLimit)
        XCTAssertTrue(restored.deletions.isEmpty)
    }

    func testPreviouslyClosedActiveCardsCanBeUndoneWithoutANewSnapshotField() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: "Build", progress: 25, etaSeconds: 60))
        let id = try XCTUnwrap(registry.items.first?.id)
        registry.close(id: id)
        var snapshot = registry.snapshot
        snapshot.closures = nil // State written before Shift+Z existed.
        let restored = ProgressRegistry(snapshot: snapshot)
        XCTAssertEqual(restored.undoClose()?.id, id)
        XCTAssertEqual(restored.visibleItems.map(\.id), [id])
    }

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
