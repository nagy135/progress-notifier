import XCTest
import ProgressCore
@testable import ProgressNotifier

final class DescriptionAPITests: XCTestCase {
    func testDescriptionAPIValidatesAndReturnsRecordedSnapshots() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ProgressModel(stateURL: directory.appendingPathComponent("state.json"))
        func request(_ method: String, _ value: [String: Any]? = nil) throws -> HTTPResponse {
            let body = try value.map { try JSONSerialization.data(withJSONObject: $0) } ?? Data()
            var wire = Data("\(method) /items HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
            wire.append(body)
            return model.handle(try XCTUnwrap(HTTPRequest.parse(wire)))
        }
        let update: [String: Any] = ["name": "Build", "progress": 25, "etaSeconds": 30, "description": "Compiled"]
        XCTAssertEqual(try request("POST", update).status, 200)
        XCTAssertEqual(try request("POST", update).status, 200)
        for invalid: Any in [42, ["nested": "object"], String(repeating: "x", count: 2001)] {
            var bad = update
            bad["description"] = invalid
            XCTAssertEqual(try request("POST", bad).status, 400)
        }
        XCTAssertEqual(try request("POST", ["name": "Build", "progress": 50, "etaSeconds": 20]).status, 200)
        let response = try request("GET")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let item = try XCTUnwrap((json["items"] as? [[String: Any]])?.first)
        XCTAssertEqual(item["description"] as? String, "Compiled")
        XCTAssertEqual(item["progress"] as? Int, 50)
        XCTAssertEqual(item["updateCount"] as? Int, 1)
        let entry = try XCTUnwrap((item["updates"] as? [[String: Any]])?.first)
        XCTAssertEqual(entry["progress"] as? Int, 25)
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(entry["id"] as? String)))
        let timestamp = ISO8601DateFormatter()
        timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertNotNil(timestamp.date(from: try XCTUnwrap(entry["recordedAt"] as? String)))
    }
}
