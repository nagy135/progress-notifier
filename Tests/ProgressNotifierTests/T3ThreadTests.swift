import AppKit
import XCTest
import ProgressCore
@testable import ProgressNotifier

final class T3ThreadTests: XCTestCase {
    func testOpeningSelectedTaskTargetsBetaAndActivatesItInBothModes() throws {
        let registry = ProgressRegistry()
        let first = T3ThreadReference(environmentId: "mac", threadId: "first")
        let second = T3ThreadReference(environmentId: "remote", threadId: "second")
        for (name, reference) in [("First", first), ("Second", second), ("Unlinked", nil)] {
            try registry.update(.init(name: name, progress: 10, etaSeconds: 60, t3Thread: reference))
        }
        for compact in [false, true] {
            let presentation = ProgressPresentation(compact: compact)
            presentation.update(items: registry.items, compact: compact, animated: false)
            var opened: [URL] = []
            let opener = T3ThreadOpener { urls, application, configuration in
                XCTAssertEqual(application.path, "/Applications/T3 Code (Beta).app")
                XCTAssertTrue(configuration.activates)
                opened += urls
            }
            XCTAssertTrue(opener.open(presentation.focusedItem?.t3Thread))
            presentation.moveFocus(by: 1, animated: false)
            XCTAssertTrue(opener.open(presentation.focusedItem?.t3Thread))
            XCTAssertEqual(opened, [try XCTUnwrap(first.url), try XCTUnwrap(second.url)])
            presentation.moveFocus(by: 1, animated: false)
            XCTAssertFalse(opener.open(presentation.focusedItem?.t3Thread))
            presentation.update(items: [], compact: compact, animated: false)
            XCTAssertFalse(opener.open(presentation.focusedItem?.t3Thread))
            XCTAssertFalse(opener.open(.init(environmentId: "bad/path", threadId: "thread")))
            XCTAssertEqual(opened.count, 2)
        }
    }

    func testAPIRoundTripPersistenceAndMalformedReferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("state.json")
        let model = ProgressModel(stateURL: stateURL)
        func request(_ model: ProgressModel, _ method: String, reference: Any? = nil, progress: Int = 10) throws -> HTTPResponse {
            var value: [String: Any] = ["name": "Build", "progress": progress, "etaSeconds": 60]
            value["t3Thread"] = reference
            let body = try JSONSerialization.data(withJSONObject: value)
            var wire = Data("\(method) /items HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
            wire.append(body)
            return model.handle(try XCTUnwrap(HTTPRequest.parse(wire)))
        }
        let reference = ["environmentId": "mac", "threadId": "thread"]
        XCTAssertEqual(try request(model, "POST", reference: reference).status, 200)
        for bad: Any in ["thread", 42, [:], ["threadId": "thread"], ["environmentId": "mac", "threadId": 42],
                         ["environmentId": "mac", "threadId": "thread?prompt=bad"]] {
            XCTAssertEqual(try request(model, "POST", reference: bad, progress: 99).status, 400)
        }
        XCTAssertEqual(try request(model, "POST", reference: NSNull(), progress: 20).status, 200)
        XCTAssertEqual(try request(model, "POST", progress: 30).status, 200)
        let restored = ProgressModel(stateURL: stateURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request(restored, "GET").body) as? [String: Any])
        let item = try XCTUnwrap((json["items"] as? [[String: Any]])?.first)
        XCTAssertEqual(item["t3Thread"] as? [String: String], reference)
        XCTAssertEqual(item["progress"] as? Int, 30)
    }
}
