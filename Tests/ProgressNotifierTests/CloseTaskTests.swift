import XCTest
import ProgressCore
@testable import ProgressNotifier

final class CloseTaskTests: XCTestCase {
    func testUndoCloseRestoresPersistedActiveAndCompletedCardsWithoutEffectsOrUnbanning() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = ProgressRegistry()
        for name in ["Closed", "Banned", "Completed"] {
            try registry.update(.init(name: name, progress: 25, etaSeconds: 60, description: "Started"))
        }
        let ids = registry.items.map(\.id)
        registry.close(id: ids[0])
        registry.dismiss(id: ids[1])
        try registry.update(.init(name: "Completed", progress: 100, etaSeconds: 0))
        registry.close(id: ids[2])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("state.json")
        try JSONEncoder().encode(registry.snapshot).write(to: stateURL)
        var feedback = 0
        let model = ProgressModel(stateURL: stateURL, completionFeedback: { feedback += 1 })
        XCTAssertTrue(model.displayItems.isEmpty)
        XCTAssertEqual(model.undoClose()?.id, ids[2])
        XCTAssertEqual(model.displayItems.map(\.id), [ids[2]])
        XCTAssertFalse(model.consumeUpdatePulse(for: try XCTUnwrap(model.displayItems.first)))
        let relaunched = ProgressModel(stateURL: stateURL, completionFeedback: { feedback += 1 })
        XCTAssertEqual(relaunched.undoClose()?.id, ids[0])
        XCTAssertEqual(relaunched.displayItems.map(\.id), [ids[0]])
        XCTAssertEqual(relaunched.displayItems.first?.updates.map(\.description), ["Started"])
        XCTAssertFalse(relaunched.consumeUpdatePulse(for: try XCTUnwrap(relaunched.displayItems.first)))
        XCTAssertNil(relaunched.undoClose())
        XCTAssertEqual(relaunched.undoDeletion()?.id, ids[1])
        XCTAssertEqual(feedback, 0)
    }

    func testCloseHidesCardUntilHTTPUpdateAndKeepsNotesAndCompletionFeedback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("state.json")
        var feedback = 0
        let model = ProgressModel(stateURL: stateURL, completionFeedback: { feedback += 1 })
        func post(_ progress: Int) throws {
            let body = try JSONSerialization.data(withJSONObject: ["name": "Build", "progress": progress,
                "etaSeconds": 30, "description": "At \(progress)"])
            var wire = Data("POST /items HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
            wire.append(body)
            XCTAssertEqual(model.handle(try XCTUnwrap(HTTPRequest.parse(wire))).status, 200)
        }
        try post(25)
        let item = try XCTUnwrap(model.displayItems.first)
        _ = model.consumeUpdatePulse(for: item)
        model.close(item)
        XCTAssertTrue(model.displayItems.isEmpty)
        XCTAssertEqual(model.items.map(\.id), [item.id], "Closed work must remain tracked")
        XCTAssertNil(model.undoDeletion())
        let restored = ProgressModel(stateURL: stateURL)
        XCTAssertTrue(restored.displayItems.isEmpty)
        XCTAssertEqual(restored.items.map(\.id), [item.id])

        try post(50)
        let updated = try XCTUnwrap(model.displayItems.first)
        XCTAssertEqual(updated.id, item.id)
        XCTAssertEqual(updated.updates.map(\.description), ["At 50", "At 25"])
        XCTAssertTrue(model.consumeUpdatePulse(for: updated))
        model.close(updated)
        try post(100)
        XCTAssertEqual(feedback, 1)
        XCTAssertEqual(model.displayItems.map(\.id), [item.id])
        XCTAssertEqual(model.displayItems.first?.progress, 100)
        model.close(try XCTUnwrap(model.displayItems.first))
        XCTAssertTrue(model.displayItems.isEmpty)
        XCTAssertTrue(model.hasHistory)
        XCTAssertTrue(model.recallCompleted())
        XCTAssertEqual(model.displayItems.map(\.id), [item.id])
    }
}
