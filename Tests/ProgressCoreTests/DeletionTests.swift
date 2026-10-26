import XCTest
@testable import ProgressCore

final class DeletionTests: XCTestCase {
    private func start(_ name: String, in registry: ProgressRegistry) throws {
        try registry.update(.init(name: name, progress: 25, etaSeconds: 60, project: "Project", description: "Started"))
    }

    func testDeletionIgnoresEveryUpdateUntilUndoIncludingAfterCompletion() throws {
        let registry = ProgressRegistry()
        try start("Build", in: registry)
        let item = try XCTUnwrap(registry.items.first)
        registry.dismiss(id: item.id)
        for progress in [50.0, 100, 0, 75] {
            XCTAssertFalse(try registry.update(.init(name: " Build ", progress: progress, etaSeconds: 1,
                                                     project: "Changed", description: "Ignored")))
        }
        XCTAssertTrue(registry.items.isEmpty)
        XCTAssertTrue(registry.history.isEmpty)
        XCTAssertEqual(registry.deletions.first?.item.updates.map(\.description), ["Started"])
        XCTAssertTrue(registry.undoDeletion())
        XCTAssertEqual(registry.items.first?.id, item.id)
        XCTAssertEqual(registry.items.first?.progress, item.progress)
        XCTAssertEqual(registry.items.first?.expectedFinish, item.expectedFinish)
        XCTAssertEqual(registry.items.first?.project, "Project")
        try registry.update(.init(name: "Build", progress: 60, etaSeconds: 20, description: "Resumed"))
        XCTAssertEqual(registry.items.first?.progress, 60)
        XCTAssertEqual(registry.items.first?.updates.map(\.description), ["Resumed", "Started"])
        XCTAssertTrue(try registry.update(.init(name: "Build", progress: 100, etaSeconds: 0)))
    }

    func testLIFOStackAndSuppressionSurviveRelaunch() throws {
        let registry = ProgressRegistry()
        for name in ["First", "Second", "Third"] { try start(name, in: registry) }
        let ids = registry.items.map(\.id)
        registry.dismiss(name: "Second")
        registry.dismiss(name: "First")
        registry.dismiss(name: "First") // Repeated DELETE must not add another entry.
        let snapshot = try JSONDecoder().decode(ProgressSnapshot.self, from: JSONEncoder().encode(registry.snapshot))
        let restored = ProgressRegistry(snapshot: snapshot)
        try restored.update(.init(name: "First", progress: 100, etaSeconds: 0))
        try restored.update(.init(name: "First", progress: 1, etaSeconds: 0))
        XCTAssertEqual(restored.items.map(\.name), ["Third"])
        XCTAssertTrue(restored.undoDeletion())
        XCTAssertEqual(restored.items.map(\.name), ["First", "Third"])
        try restored.update(.init(name: "Second", progress: 50, etaSeconds: 0))
        XCTAssertEqual(restored.items.count, 2)
        XCTAssertTrue(restored.undoDeletion())
        XCTAssertEqual(restored.items.map(\.id), ids)
        XCTAssertFalse(restored.undoDeletion())
    }

    func testDeletedResultsCannotBeRecalledOrUpdatedUntilUndone() throws {
        let registry = ProgressRegistry()
        try start("Build", in: registry)
        try registry.update(.init(name: "Build", progress: 100, etaSeconds: 0))
        let id = try XCTUnwrap(registry.items.first?.id)
        registry.dismiss(id: id)
        registry.removeCompleted(id: id) // Original asynchronous retirement callback.
        registry.clearCompleted()
        XCTAssertFalse(registry.revealNextCompleted())
        try start("Build", in: registry)
        XCTAssertTrue(registry.items.isEmpty)
        let restored = ProgressRegistry(snapshot: registry.snapshot)
        XCTAssertTrue(restored.undoDeletion())
        XCTAssertEqual(restored.revealedHistory.map(\.id), [id])
        XCTAssertTrue(restored.items.isEmpty)
        restored.removeCompleted(id: id)
        XCTAssertEqual(restored.revealedHistory.map(\.id), [id])
        try restored.update(.init(name: "Build", progress: 50, etaSeconds: 10))
        XCTAssertEqual(restored.items.first?.progress, 50)
    }

    func testUndoAtCapacityKeepsDeletionForLater() throws {
        let registry = ProgressRegistry()
        try start("Deleted", in: registry)
        registry.dismiss(name: "Deleted")
        for index in 0..<50 { try start("Task \(index)", in: registry) }
        XCTAssertFalse(registry.undoDeletion())
        XCTAssertEqual(registry.deletions.count, 1)
        try registry.update(.init(name: "Task 0", progress: 100, etaSeconds: 0))
        registry.removeCompleted(id: registry.items[0].id)
        XCTAssertTrue(registry.undoDeletion())
        XCTAssertEqual(registry.items.first?.name, "Deleted")
    }
}
