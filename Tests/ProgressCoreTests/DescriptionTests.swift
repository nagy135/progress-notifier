import XCTest
@testable import ProgressCore

final class DescriptionTests: XCTestCase {
    func testDescriptionsAreImmutableNewestFirstSnapshotsInReceiptOrder() throws {
        let registry = ProgressRegistry()
        let now = Date(timeIntervalSince1970: 1000)
        try registry.update(.init(name: "Build", progress: 60, etaSeconds: 30, description: "Compiled"), now: now)
        try registry.update(.init(name: "Build", progress: 25, etaSeconds: 60, description: "Added more work"), now: now)
        XCTAssertEqual(registry.items[0].updates.map(\.progress), [25, 60])
        XCTAssertEqual(registry.items[0].updates.map(\.description), ["Added more work", "Compiled"])
        XCTAssertEqual(Set(registry.items[0].updates.map(\.id)).count, 2)
        let note = registry.items[0].updates[0]
        try registry.update(.init(name: "Build", progress: 80, etaSeconds: 10))
        XCTAssertEqual(registry.items[0].progress, 80)
        XCTAssertEqual(registry.items[0].updates[0].id, note.id)
        XCTAssertEqual(registry.items[0].updates[0].progress, 25)
    }

    func testConsecutiveRetriesOmissionsAndDistinctPairs() throws {
        let registry = ProgressRegistry()
        let now = Date(timeIntervalSince1970: 1000)
        try registry.update(.init(name: "Build", progress: 20, etaSeconds: 60, description: "  Compiled\r\nTests next  "), now: now)
        let note = registry.items[0].updates[0]
        for description: String? in ["Compiled\nTests next", nil, "\n\t "] {
            try registry.update(.init(name: "Build", progress: 20, etaSeconds: 30, description: description), now: now.addingTimeInterval(5))
        }
        XCTAssertEqual(registry.items[0].updates.count, 1)
        XCTAssertEqual(registry.items[0].updates[0].id, note.id)
        XCTAssertEqual(registry.items[0].updates[0].recordedAt, now)
        XCTAssertEqual(registry.items[0].expectedFinish, now.addingTimeInterval(35))
        try registry.update(.init(name: "Build", progress: 30, etaSeconds: 20, description: "Compiled\nTests next"))
        try registry.update(.init(name: "Build", progress: 30, etaSeconds: 20, description: "Started tests"))
        XCTAssertEqual(registry.items[0].updates.count, 3)
    }

    func testDescriptionValidationIsAtomic() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: "Build", progress: 20, etaSeconds: 60, description: "Good"))
        for description in [String(repeating: "a", count: 2001), "Bad\u{0}text", "Bad\u{7f}text"] {
            XCTAssertThrowsError(try registry.update(.init(name: "Build", progress: 80, etaSeconds: 0, description: description)))
            XCTAssertEqual(registry.items[0].progress, 20)
            XCTAssertEqual(registry.items[0].updates.count, 1)
        }
        try registry.update(.init(name: "Build", progress: 30, etaSeconds: 40, description: String(repeating: "a", count: 2000)))
        XCTAssertEqual(registry.items[0].updates.first?.description.count, 2000)
    }

    func testNotesPersistThroughCompletionRecallAndRelaunch() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: "Build", progress: 20, etaSeconds: 60, description: "Started"))
        try registry.update(.init(name: "Build", progress: 100, etaSeconds: 0, description: "Passed"))
        let ids = registry.items[0].updates.map(\.id)
        registry.clearCompleted()
        let data = try JSONEncoder().encode(registry.snapshot)
        let restored = ProgressRegistry(snapshot: try JSONDecoder().decode(ProgressSnapshot.self, from: data))
        XCTAssertTrue(restored.revealNextCompleted())
        XCTAssertEqual(restored.revealedHistory[0].updates.map(\.id), ids)
        XCTAssertEqual(restored.revealedHistory[0].updates.map(\.progress), [100, 20])
        try restored.update(.init(name: "Build", progress: 5, etaSeconds: 60))
        XCTAssertTrue(restored.items[0].updates.isEmpty)
    }

    func testNotesAreBoundedAndLegacyItemsDecodeWithoutThem() throws {
        let registry = ProgressRegistry()
        for index in 0...ProgressRegistry.updateLimit {
            try registry.update(.init(name: "Build", progress: 10, etaSeconds: 60, description: "Step \(index)"))
        }
        XCTAssertEqual(registry.items[0].updates.count, 200)
        XCTAssertEqual(registry.items[0].updates.first?.description, "Step 200")
        XCTAssertEqual(registry.items[0].updates.last?.description, "Step 1")
        let data = try JSONEncoder().encode(registry.snapshot)
        let restored = ProgressRegistry(snapshot: try JSONDecoder().decode(ProgressSnapshot.self, from: data))
        XCTAssertEqual(restored.items[0].updates.count, 200)
        let legacy = #"{"items":[{"id":"0A201158-069C-4E7B-A850-D7D2AC46F548","name":"Old","progress":10,"expectedFinish":1000,"completing":false}],"dismissed":[]}"#
        let old = ProgressRegistry(snapshot: try JSONDecoder().decode(ProgressSnapshot.self, from: Data(legacy.utf8)))
        XCTAssertTrue(old.items[0].updates.isEmpty)
    }
}
