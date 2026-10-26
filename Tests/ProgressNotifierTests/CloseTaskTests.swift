import XCTest
import ProgressCore
@testable import ProgressNotifier

final class CloseTaskTests: XCTestCase {
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
