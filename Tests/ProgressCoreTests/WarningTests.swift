import XCTest
@testable import ProgressCore

final class WarningTests: XCTestCase {
    func testAcknowledgementClearsOnlySelectedWarningWithoutChangingTimingOrReplayingCompletion() throws {
        let registry = ProgressRegistry()
        let now = Date(timeIntervalSince1970: 1000)
        for name in ["First", "Second"] {
            try registry.update(.init(name: name, progress: 42, etaSeconds: 90, warning: "Question?"), now: now)
        }
        let first = registry.items[0]
        XCTAssertTrue(registry.acknowledgeWarning(id: first.id, now: now.addingTimeInterval(5)))
        XCTAssertNil(registry.items[0].warning)
        XCTAssertEqual(registry.items[0].expectedFinish, first.expectedFinish)
        XCTAssertEqual(registry.items[0].progress, first.progress)
        XCTAssertFalse(registry.items[0].completing)
        XCTAssertEqual(registry.items[1].warning, "Question?")
        XCTAssertEqual(registry.items[0].updates.first?.description, "Warning acknowledged")
        XCTAssertEqual(registry.items[0].updates.last?.warning, "Question?")
        XCTAssertFalse(registry.acknowledgeWarning(id: first.id))
        XCTAssertEqual(registry.items[0].updates.count, 2)
        // Ordinary agent updates cannot silently reintroduce the acknowledged warning.
        try registry.update(.init(name: "First", progress: 60, etaSeconds: 20))
        XCTAssertNil(registry.items[0].warning)
        try registry.update(.init(name: "First", progress: 100, etaSeconds: 0, warning: "New issue"))
        XCTAssertTrue(registry.acknowledgeWarning(id: first.id))
        XCTAssertNil(registry.items[0].warning)
        XCTAssertNil(registry.history[0].warning)
        XCTAssertEqual(registry.items[0].updates.map(\.id), registry.history[0].updates.map(\.id))
        registry.clearCompleted()
        XCTAssertTrue(registry.revealNextCompleted())
        XCTAssertNil(registry.revealedHistory[0].warning)
    }

    func testWarningIsTaskScopedStickyAndExplicitlyClearedWithHistory() throws {
        let registry = ProgressRegistry()
        let now = Date(timeIntervalSince1970: 1000)
        try registry.update(.init(name: "Release", progress: 20, etaSeconds: 60,
                                  description: "Uploading", warning: "  Include symbols?\r\nContinuing checks.  "), now: now)
        try registry.update(.init(name: "Other", progress: 10, etaSeconds: 20))
        let id = registry.items[0].id
        XCTAssertNil(registry.items[1].warning)
        try registry.update(.init(name: "Release", progress: 40, etaSeconds: 30), now: now)
        XCTAssertEqual(registry.items[0].warning, "Include symbols?\nContinuing checks.")
        XCTAssertEqual(registry.items[0].updates.count, 1)
        XCTAssertEqual(registry.items[0].expectedFinish, now.addingTimeInterval(30))
        try registry.update(.init(name: "Release", progress: 40, etaSeconds: 30,
                                  description: "Uploading", warning: "Retrying"), now: now)
        // Identical progress and description must still record a changed warning.
        XCTAssertEqual(registry.items[0].updates.count, 2)
        try registry.update(.init(name: "Release", progress: 60, etaSeconds: 10, warning: ""))
        XCTAssertEqual(registry.items[0].id, id)
        XCTAssertNil(registry.items[0].warning)
        XCTAssertEqual(registry.items[0].updates.map(\.warning), [nil, "Retrying", "Include symbols?\nContinuing checks."])
        XCTAssertEqual(registry.items[0].updates.first?.description, "Warning cleared")
    }

    func testWarningSurvivesPersistenceUndoCompletionAndRecallButNotNewRun() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: "Build", progress: 0, etaSeconds: 60, warning: "Check output"))
        let data = try JSONEncoder().encode(registry.snapshot)
        let restored = ProgressRegistry(snapshot: try JSONDecoder().decode(ProgressSnapshot.self, from: data))
        XCTAssertEqual(restored.items.first?.warning, "Check output")
        restored.dismiss(name: "Build")
        _ = restored.undoDeletion()
        XCTAssertEqual(restored.items.first?.warning, "Check output")
        try restored.update(.init(name: "Build", progress: 100, etaSeconds: 0))
        restored.clearCompleted()
        XCTAssertTrue(restored.revealNextCompleted())
        XCTAssertEqual(restored.revealedHistory.first?.warning, "Check output")
        try restored.update(.init(name: "Build", progress: 10, etaSeconds: 30))
        XCTAssertNil(restored.items.first?.warning)
        XCTAssertTrue(restored.items.first?.updates.isEmpty == true)
    }

    func testInvalidWarningsCannotMutateTaskAndLegacySnapshotsRemainCompatible() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: "Build", progress: 20, etaSeconds: 60, warning: "Good"))
        for warning in [String(repeating: "x", count: 2001), "bad\u{0}", "bad\u{7f}"] {
            XCTAssertThrowsError(try registry.update(.init(name: "Build", progress: 90, etaSeconds: 0, warning: warning)))
            XCTAssertEqual(registry.items[0].progress, 20)
            XCTAssertEqual(registry.items[0].warning, "Good")
        }
        let data = try JSONEncoder().encode(registry.snapshot)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var items = try XCTUnwrap(json["items"] as? [[String: Any]])
        items[0].removeValue(forKey: "warning")
        var updates = try XCTUnwrap(items[0]["updates"] as? [[String: Any]])
        updates[0].removeValue(forKey: "warning")
        items[0]["updates"] = updates
        json["items"] = items
        let old = ProgressRegistry(snapshot: try JSONDecoder().decode(ProgressSnapshot.self, from: JSONSerialization.data(withJSONObject: json)))
        XCTAssertNil(old.items[0].warning)
        XCTAssertNil(old.items[0].updates[0].warning)
    }
}
