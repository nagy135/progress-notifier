import XCTest
import ProgressCore
@testable import ProgressNotifier

final class CompletedTaskTests: XCTestCase {
    private func update(_ model: ProgressModel, name: String = "Build", progress: Int, description: String) throws {
        let body = try JSONSerialization.data(withJSONObject: ["name": name, "progress": progress,
                                                              "etaSeconds": 0, "description": description])
        var wire = Data("POST /items HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        wire.append(body)
        XCTAssertEqual(model.handle(try XCTUnwrap(HTTPRequest.parse(wire))).status, 200)
    }

    private func waitForCompletionRetirement() {
        let finished = expectation(description: "API completion phase has retired")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { finished.fulfill() }
        wait(for: [finished], timeout: 3)
    }

    func testCompletionStaysAsOneHistoryCardAndDoesNotBlockNewRun() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var feedbackCount = 0
        let model = ProgressModel(stateURL: directory.appendingPathComponent("state.json"), completionFeedback: { feedbackCount += 1 })
        try update(model, progress: 10, description: "Started")
        let id = try XCTUnwrap(model.displayItems.first?.id)
        try update(model, progress: 100, description: "Passed")
        XCTAssertEqual(model.displayItems.map(\.id), [id], "Completion must not duplicate the live/history record")
        XCTAssertEqual(model.displayItems[0].updates.map(\.description), ["Passed", "Started"])
        XCTAssertFalse(model.recallCompleted())
        try update(model, progress: 100, description: "Passed")
        XCTAssertEqual(feedbackCount, 1)
        waitForCompletionRetirement()
        XCTAssertTrue(model.items.isEmpty, "Completed results must not occupy active task names or capacity")
        XCTAssertEqual(model.displayItems.map(\.id), [id], "The card must remain after completion feedback ends")
        XCTAssertFalse(model.consumeUpdatePulse(for: model.displayItems[0]))
        try update(model, progress: 5, description: "New run")
        XCTAssertEqual(model.displayItems.count, 2)
        XCTAssertEqual(model.items[0].progress, 5)
        XCTAssertNotEqual(model.items[0].id, id)
        model.dismiss(try XCTUnwrap(model.recalledItems.first))
        XCTAssertEqual(model.displayItems.map(\.id), model.items.map(\.id))
        XCTAssertEqual(feedbackCount, 1)
    }

    func testClearDuringCompletionDoesNotResurfaceWhenFeedbackEnds() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ProgressModel(stateURL: directory.appendingPathComponent("state.json"), completionFeedback: {})
        try update(model, progress: 10, description: "Started")
        try update(model, progress: 100, description: "Passed")
        let id = try XCTUnwrap(model.displayItems.first?.id)
        model.clearCompleted()
        XCTAssertTrue(model.displayItems.isEmpty)
        waitForCompletionRetirement()
        XCTAssertTrue(model.displayItems.isEmpty)
        XCTAssertTrue(model.recallCompleted())
        XCTAssertEqual(model.displayItems.map(\.id), [id])
    }

    func testDismissingFinishingCardAndRetainedResultBothHideTheCard() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ProgressModel(stateURL: directory.appendingPathComponent("state.json"), completionFeedback: {})
        try update(model, progress: 10, description: "Started")
        try update(model, progress: 100, description: "Passed")
        model.dismiss(try XCTUnwrap(model.displayItems.first))
        XCTAssertTrue(model.displayItems.isEmpty)
        waitForCompletionRetirement()
        XCTAssertTrue(model.displayItems.isEmpty)
        XCTAssertFalse(model.hasHistory)
        model.clearCompleted()
        XCTAssertFalse(model.recallCompleted())
        XCTAssertNotNil(model.undoDeletion())
        model.dismiss("Build")
        XCTAssertTrue(model.displayItems.isEmpty)
    }
}
