import XCTest
@testable import ProgressCore

final class RunRelationshipTests: XCTestCase {
    let chat = T3ThreadReference(environmentId: "mac", threadId: "chat")

    func testLinksSurviveOmittedUpdatesHistoryCloseDeleteUndoAndRelaunch() throws {
        let registry = ProgressRegistry()
        let parent = UUID(), run = UUID()
        try registry.update(.init(name: "Main", progress: 0, etaSeconds: 60, t3Thread: chat, runId: parent))
        try registry.update(.init(name: "Child", progress: 0, etaSeconds: 60, t3Thread: chat, isChild: true,
                                  runId: run, parentRunId: parent))
        try registry.update(.init(name: "Child", progress: 50, etaSeconds: 30))
        let id = try XCTUnwrap(registry.items.last?.id)
        registry.close(id: id)
        let restored = try reload(registry)
        XCTAssertEqual(restored.undoClose()?.parentRunId, parent)
        restored.dismiss(id: id)
        let undeleted = try reload(restored)
        XCTAssertTrue(undeleted.undoDeletion())
        XCTAssertEqual(undeleted.items.last?.runId, run)
        try undeleted.update(.init(name: "Child", progress: 100, etaSeconds: 0))
        let completed = try reload(undeleted)
        XCTAssertTrue(completed.revealNextCompleted())
        XCTAssertEqual(completed.revealedHistory.first?.parentRunId, parent)
        // A terminal retry cannot create another card or attach a new run to that ID.
        try completed.update(.init(name: "Child", progress: 30, etaSeconds: 40, runId: run))
        XCTAssertFalse(completed.items.contains { $0.name == "Child" })
        try completed.update(.init(name: "Child", progress: 0, etaSeconds: 60))
        XCTAssertNil(completed.items.last?.runId)
        XCTAssertNil(completed.items.last?.parentRunId)
    }

    func testRejectsIdentityConflictsAndInvalidEdgesWithoutPartialMutation() throws {
        let registry = ProgressRegistry()
        let parent = UUID(), child = UUID()
        try registry.update(.init(name: "Main", progress: 10, etaSeconds: 60, t3Thread: chat, runId: parent))
        try registry.update(.init(name: "Child", progress: 20, etaSeconds: 60, t3Thread: chat, isChild: true,
                                  runId: child, parentRunId: parent))
        for update in [
            ProgressUpdate(name: "Other", progress: 0, etaSeconds: 1, runId: parent),
            .init(name: "Main", progress: 99, etaSeconds: 1, runId: UUID()),
            .init(name: "Child", progress: 99, etaSeconds: 1, isChild: false),
            .init(name: "Child", progress: 99, etaSeconds: 1, t3Thread: .init(environmentId: "mac", threadId: "other")),
            .init(name: "Main", progress: 99, etaSeconds: 1, isChild: true, runId: parent, parentRunId: child)
        ] {
            XCTAssertThrowsError(try registry.update(update))
        }
        XCTAssertEqual(registry.items.map(\.progress), [10, 20])
        XCTAssertThrowsError(try registry.update(.init(name: "Self", progress: 0, etaSeconds: 1, isChild: true,
                                                      runId: parent, parentRunId: parent)))
    }

    func testOutOfOrderParentsValidateWaitingChildrenAndCycles() throws {
        let registry = ProgressRegistry()
        let a = UUID(), b = UUID()
        try registry.update(.init(name: "Child first", progress: 0, etaSeconds: 60, t3Thread: chat,
                                  isChild: true, runId: b, parentRunId: a))
        XCTAssertThrowsError(try registry.update(.init(name: "Wrong chat", progress: 0, etaSeconds: 60,
                                                      runId: a)))
        XCTAssertThrowsError(try registry.update(.init(name: "Cycle", progress: 0, etaSeconds: 60, t3Thread: chat,
                                                      isChild: true, runId: a, parentRunId: b)))
        try registry.update(.init(name: "Parent later", progress: 0, etaSeconds: 60, t3Thread: chat, runId: a))
        XCTAssertEqual(registry.items.count, 2)
    }

    private func reload(_ registry: ProgressRegistry) throws -> ProgressRegistry {
        ProgressRegistry(snapshot: try JSONDecoder().decode(ProgressSnapshot.self, from: JSONEncoder().encode(registry.snapshot)))
    }
}
