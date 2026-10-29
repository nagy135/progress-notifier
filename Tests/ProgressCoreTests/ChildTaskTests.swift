import XCTest
@testable import ProgressCore

final class ChildTaskTests: XCTestCase {
    func testMarkerSurvivesLifecycleButDoesNotLeakIntoNewRun() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: "Review", progress: 0, etaSeconds: 60, isChild: true))
        try registry.update(.init(name: "Review", progress: 50, etaSeconds: 30))
        let restored = try reload(registry)
        XCTAssertTrue(try XCTUnwrap(restored.items.first).isChild)
        restored.close(id: try XCTUnwrap(restored.items.first?.id))
        XCTAssertTrue(try XCTUnwrap(try reload(restored).undoClose()).isChild)
        restored.dismiss(id: try XCTUnwrap(restored.items.first?.id))
        let undeleted = try reload(restored)
        XCTAssertTrue(undeleted.undoDeletion())
        XCTAssertTrue(try XCTUnwrap(undeleted.items.first).isChild)
        try undeleted.update(.init(name: "Review", progress: 100, etaSeconds: 0))
        undeleted.clearCompleted()
        let completed = try reload(undeleted)
        XCTAssertTrue(completed.revealNextCompleted())
        XCTAssertTrue(try XCTUnwrap(completed.revealedHistory.first).isChild)
        try completed.update(.init(name: "Review", progress: 0, etaSeconds: 60))
        XCTAssertFalse(try XCTUnwrap(completed.items.first).isChild)
    }

    func testExplicitFalseCorrectsMarkerAndLegacyStateDefaultsToRegular() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: "Review", progress: 0, etaSeconds: 60, isChild: true))
        try registry.update(.init(name: "Review", progress: 10, etaSeconds: 30, isChild: false))
        XCTAssertFalse(try XCTUnwrap(try reload(registry).items.first).isChild)
        let data = try JSONEncoder().encode(registry.snapshot)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var items = try XCTUnwrap(json["items"] as? [[String: Any]])
        items[0].removeValue(forKey: "isChild")
        json["items"] = items
        let legacy = try JSONDecoder().decode(ProgressSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(try XCTUnwrap(ProgressRegistry(snapshot: legacy).items.first).isChild)
    }

    private func reload(_ registry: ProgressRegistry) throws -> ProgressRegistry {
        ProgressRegistry(snapshot: try JSONDecoder().decode(ProgressSnapshot.self, from: JSONEncoder().encode(registry.snapshot)))
    }
}
