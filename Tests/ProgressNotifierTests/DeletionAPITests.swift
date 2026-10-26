import XCTest
import ProgressCore
@testable import ProgressNotifier

final class DeletionAPITests: XCTestCase {
    func testDeletedUpdatesAreAcknowledgedWithoutPublishingSavingOrFeedbackAndUndoResumes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("state.json")
        var feedback = 0
        var publications = 0
        let model = ProgressModel(stateURL: stateURL, completionFeedback: { feedback += 1 })
        model.changed = { publications += 1 }
        func request(_ method: String, target: String = "/items", progress: Int? = nil) throws -> HTTPResponse {
            let body = try progress.map { try JSONSerialization.data(withJSONObject: [
                "name": "Build", "progress": $0, "etaSeconds": 30, "description": "At \($0)"
            ]) } ?? Data()
            var wire = Data("\(method) \(target) HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
            wire.append(body)
            return model.handle(try XCTUnwrap(HTTPRequest.parse(wire)))
        }
        XCTAssertEqual(try request("POST", progress: 10).status, 200)
        let item = try XCTUnwrap(model.items.first)
        XCTAssertTrue(model.consumeUpdatePulse(for: item))
        XCTAssertEqual(try request("DELETE", target: "/items?name=Build").status, 200)
        let saved = try Data(contentsOf: stateURL)
        let published = publications
        for progress in [50, 100, 0, 75] {
            XCTAssertEqual(try request("POST", progress: progress).status, 200)
        }
        XCTAssertEqual(try request("POST", progress: 101).status, 400)
        XCTAssertEqual(publications, published)
        XCTAssertEqual(try Data(contentsOf: stateURL), saved)
        XCTAssertEqual(feedback, 0)
        XCTAssertTrue(model.displayItems.isEmpty)
        let list = try JSONSerialization.jsonObject(with: request("GET").body) as? [String: Any]
        XCTAssertEqual((list?["items"] as? [[String: Any]])?.count, 0)

        let relaunched = ProgressModel(stateURL: stateURL, completionFeedback: { feedback += 1 })
        XCTAssertEqual(relaunched.undoDeletion()?.id, item.id)
        XCTAssertEqual(relaunched.items.first?.updates.map(\.description), ["At 10"])
        XCTAssertFalse(relaunched.consumeUpdatePulse(for: try XCTUnwrap(relaunched.items.first)))
        XCTAssertNil(relaunched.undoDeletion())
        // The original instance also resumes only when its own stack is undone.
        XCTAssertEqual(model.undoDeletion()?.id, item.id)
        XCTAssertEqual(try request("POST", progress: 80).status, 200)
        XCTAssertEqual(model.items.first?.progress, 80)
        XCTAssertTrue(model.consumeUpdatePulse(for: try XCTUnwrap(model.items.first)))
        XCTAssertEqual(try request("POST", progress: 100).status, 200)
        XCTAssertEqual(feedback, 1)
    }

    func testUndoRestoresSelectedTaskAndItsPosition() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = ProgressRegistry()
        for name in ["First", "Second", "Third"] {
            try registry.update(.init(name: name, progress: 20, etaSeconds: 30))
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("focus.json")
        try JSONEncoder().encode(registry.snapshot).write(to: stateURL)
        let restored = ProgressModel(stateURL: stateURL)
        let presentation = ProgressPresentation(compact: false)
        presentation.update(items: restored.displayItems, compact: false, animated: false)
        presentation.moveFocus(by: 1, animated: false)
        let selected = try XCTUnwrap(presentation.focusedItem)
        restored.dismiss(selected)
        presentation.update(items: restored.displayItems, compact: false, animated: false)
        XCTAssertEqual(presentation.focusedItem?.name, "Third")
        let undone = try XCTUnwrap(restored.undoDeletion())
        presentation.update(items: restored.displayItems, compact: false, animated: false)
        presentation.focus(undone.id, animated: false)
        XCTAssertEqual(presentation.focusedItemID, selected.id)
        XCTAssertEqual(restored.displayItems.map(\.name), ["First", "Second", "Third"])
    }
}
