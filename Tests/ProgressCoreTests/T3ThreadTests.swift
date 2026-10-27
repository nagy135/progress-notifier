import XCTest
@testable import ProgressCore

final class T3ThreadTests: XCTestCase {
    private let reference = T3ThreadReference(environmentId: "mac-123", threadId: "thread_456")

    func testDestinationPersistsAcrossUpdatesCompletionRecallAndNewRun() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: "Build", progress: 10, etaSeconds: 60, t3Thread: reference))
        try registry.update(.init(name: "Build", progress: 50, etaSeconds: 30, project: ""))
        XCTAssertEqual(registry.items.first?.t3Thread, reference)
        let restored = try reload(registry)
        XCTAssertEqual(restored.items.first?.t3Thread, reference)
        restored.close(id: try XCTUnwrap(restored.items.first?.id))
        XCTAssertEqual(try reload(restored).undoClose()?.t3Thread, reference)
        restored.dismiss(id: try XCTUnwrap(restored.items.first?.id))
        let undeleted = try reload(restored)
        XCTAssertTrue(undeleted.undoDeletion())
        XCTAssertEqual(undeleted.items.first?.t3Thread, reference)
        try undeleted.update(.init(name: "Build", progress: 100, etaSeconds: 0))
        undeleted.clearCompleted()
        let completed = try reload(undeleted)
        XCTAssertTrue(completed.revealNextCompleted())
        XCTAssertEqual(completed.revealedHistory.first?.t3Thread, reference)
        try completed.update(.init(name: "Build", progress: 5, etaSeconds: 60))
        XCTAssertNil(completed.items.first?.t3Thread, "A new run must not inherit the previous run's thread")
    }

    func testReplacingDestinationAndRejectingInvalidUpdatesAtomically() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: "Build", progress: 10, etaSeconds: 60, t3Thread: reference))
        for invalid in ["", " ", "../other", "env?prompt=hello", "env#fragment", "env%2Fother", "bad\n", "é", String(repeating: "a", count: 513)] {
            for candidate in [T3ThreadReference(environmentId: invalid, threadId: "thread"),
                              T3ThreadReference(environmentId: "env", threadId: invalid)] {
                XCTAssertNil(candidate.url)
                XCTAssertThrowsError(try registry.update(.init(name: "Build", progress: 99, etaSeconds: 0, t3Thread: candidate)))
                XCTAssertEqual(registry.items.first?.progress, 10)
                XCTAssertEqual(registry.items.first?.t3Thread, reference)
            }
        }
        let replacement = T3ThreadReference(environmentId: "other", threadId: "thread")
        try registry.update(.init(name: "Build", progress: 20, etaSeconds: 30, t3Thread: replacement))
        XCTAssertEqual(registry.items.first?.t3Thread, replacement)
        XCTAssertEqual(reference.url?.absoluteString, "t3code://threads/mac-123/thread_456")
        let namespaced = T3ThreadReference(environmentId: "mac", threadId: "mcp:thread-123")
        try registry.update(.init(name: "Build", progress: 25, etaSeconds: 20, t3Thread: namespaced))
        XCTAssertEqual(try reload(registry).items.first?.t3Thread, namespaced)
        XCTAssertEqual(namespaced.url?.absoluteString, "t3code://threads/mac/mcp%3Athread-123")
    }

    func testLegacySnapshotsAndInvalidSavedDestinationsKeepTasksUsable() throws {
        let legacy = #"{"items":[{"id":"0A201158-069C-4E7B-A850-D7D2AC46F548","name":"Old","progress":10,"expectedFinish":1000,"completing":false}],"dismissed":[]}"#
        let old = ProgressRegistry(snapshot: try JSONDecoder().decode(ProgressSnapshot.self, from: Data(legacy.utf8)))
        XCTAssertEqual(old.items.count, 1)
        XCTAssertNil(old.items.first?.t3Thread)
        var snapshot = old.snapshot
        var item = try XCTUnwrap(snapshot.items.first)
        item.t3Thread = .init(environmentId: "../invalid", threadId: "thread")
        snapshot = ProgressSnapshot(items: [item], dismissed: [], history: [])
        let restored = ProgressRegistry(snapshot: snapshot)
        XCTAssertEqual(restored.items.count, 1)
        XCTAssertNil(restored.items.first?.t3Thread)
    }

    private func reload(_ registry: ProgressRegistry) throws -> ProgressRegistry {
        ProgressRegistry(snapshot: try JSONDecoder().decode(ProgressSnapshot.self, from: JSONEncoder().encode(registry.snapshot)))
    }
}
