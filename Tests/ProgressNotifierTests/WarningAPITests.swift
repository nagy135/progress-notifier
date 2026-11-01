import XCTest
import ProgressCore
@testable import ProgressNotifier

final class WarningAPITests: XCTestCase {
    func testWarningRoundTripValidationAndClearAreIndependentOfDescriptions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ProgressModel(stateURL: directory.appendingPathComponent("state.json"))
        func request(_ method: String, _ value: [String: Any]? = nil) throws -> HTTPResponse {
            let body = try value.map { try JSONSerialization.data(withJSONObject: $0) } ?? Data()
            var wire = Data("\(method) /items HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
            wire.append(body)
            return model.handle(try XCTUnwrap(HTTPRequest.parse(wire)))
        }
        func item() throws -> [String: Any] {
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request("GET").body) as? [String: Any])
            return try XCTUnwrap((json["items"] as? [[String: Any]])?.first)
        }
        let base: [String: Any] = ["name": "Build", "progress": 25, "etaSeconds": 30]
        var warning = base
        warning["warning"] = "Question? Continuing tests."
        warning["description"] = "Compiled"
        XCTAssertEqual(try request("POST", warning).status, 200)
        XCTAssertEqual(try item()["description"] as? String, "Compiled")
        XCTAssertEqual(try item()["warning"] as? String, "Question? Continuing tests.")
        for invalid: Any in [42, ["nested": "object"], String(repeating: "x", count: 2001), "bad\u{0}"] {
            var bad = base
            bad["warning"] = invalid
            XCTAssertEqual(try request("POST", bad).status, 400)
        }
        var null = base
        null["warning"] = NSNull()
        XCTAssertEqual(try request("POST", null).status, 200)
        XCTAssertNotNil(try item()["warning"])
        XCTAssertEqual(try request("POST", base).status, 200)
        XCTAssertNotNil(try item()["warning"])
        var clear = base
        clear["warning"] = ""
        XCTAssertEqual(try request("POST", clear).status, 200)
        XCTAssertNil(try item()["warning"])
        let entries = try XCTUnwrap(try item()["updates"] as? [[String: Any]])
        XCTAssertNil(entries[0]["warning"])
        XCTAssertEqual(entries[1]["warning"] as? String, "Question? Continuing tests.")
    }
}
