import XCTest
@testable import ProgressCore

final class ProgressCoreTests: XCTestCase {
    func testSnapshotRestoresIdentityEstimateAndDismissals() throws {
        let registry = ProgressRegistry()
        let now = Date(timeIntervalSince1970: 1000)
        try registry.update(.init(name: "Build", progress: 45, etaSeconds: 30), now: now)
        try registry.update(.init(name: "Tests", progress: 10, etaSeconds: 10), now: now)
        registry.dismiss(name: "Tests")
        let data = try JSONEncoder().encode(registry.snapshot)
        let restored = ProgressRegistry(snapshot: try JSONDecoder().decode(ProgressSnapshot.self, from: data))
        XCTAssertEqual(restored.items[0].id, registry.items[0].id)
        XCTAssertEqual(restored.items[0].progress, 45)
        XCTAssertEqual(restored.items[0].expectedFinish.timeIntervalSince1970, 1030)
        try restored.update(.init(name: "Tests", progress: 70, etaSeconds: 0))
        XCTAssertEqual(restored.items.count, 1)
        try restored.update(.init(name: "Tests", progress: 100, etaSeconds: 0))
        try restored.update(.init(name: "Tests", progress: 0, etaSeconds: 30))
        XCTAssertEqual(restored.items.count, 2)
    }

    func testCompletionIsNotRestoredOrReplayed() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: "Build", progress: 10, etaSeconds: 10))
        try registry.update(.init(name: "Build", progress: 100, etaSeconds: 0))
        let restored = ProgressRegistry(snapshot: registry.snapshot)
        XCTAssertTrue(restored.items.isEmpty)
    }

    func testUpdatesPreserveIdentityAndReplaceEstimate() throws {
        let registry = ProgressRegistry()
        let now = Date(timeIntervalSince1970: 1000)
        try registry.update(.init(name: "Build", progress: 0, etaSeconds: 120), now: now)
        let id = try XCTUnwrap(registry.items.first?.id)
        try registry.update(.init(name: "Build", progress: 45, etaSeconds: 20), now: now)
        try registry.update(.init(name: "Tests", progress: 10, etaSeconds: 30), now: now)
        XCTAssertEqual(registry.items.count, 2)
        XCTAssertEqual(registry.items[0].id, id)
        XCTAssertEqual(registry.items[0].progress, 45)
        XCTAssertEqual(registry.items[0].expectedFinish.timeIntervalSince1970, 1020)
    }

    func testCompletionHappensOnceAndIgnoresLateUpdates() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: "Build", progress: 10, etaSeconds: 30))
        let id = try XCTUnwrap(registry.items.first?.id)
        XCTAssertTrue(try registry.update(.init(name: "Build", progress: 100, etaSeconds: 0)))
        XCTAssertFalse(try registry.update(.init(name: "Build", progress: 100, etaSeconds: 0)))
        XCTAssertFalse(try registry.update(.init(name: "Build", progress: 70, etaSeconds: 20)))
        XCTAssertEqual(registry.items[0].progress, 100)
        registry.removeCompleted(id: id)
        XCTAssertTrue(registry.items.isEmpty)
        XCTAssertFalse(try registry.update(.init(name: "Build", progress: 100, etaSeconds: 0)))
        XCTAssertTrue(registry.items.isEmpty)
        try registry.update(.init(name: "Build", progress: 0, etaSeconds: 10))
        registry.removeCompleted(id: id)
        XCTAssertEqual(registry.items.count, 1)
    }

    func testDismissalKeepsUpdatesSilentUntilCompletion() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: " Build ", progress: 10, etaSeconds: 30))
        registry.dismiss(name: "Build")
        try registry.update(.init(name: "Build", progress: 50, etaSeconds: 10))
        XCTAssertTrue(registry.items.isEmpty)
        try registry.update(.init(name: "Build", progress: 100, etaSeconds: 0))
        XCTAssertTrue(registry.items.isEmpty)
        try registry.update(.init(name: "Build", progress: 0, etaSeconds: 30))
        XCTAssertEqual(registry.items.count, 1)
    }

    func testInvalidInputDoesNotChangeState() throws {
        let registry = ProgressRegistry()
        for value in [
            ProgressUpdate(name: " ", progress: 10, etaSeconds: 10),
            .init(name: "a\nb", progress: 10, etaSeconds: 10),
            .init(name: "Build", progress: -1, etaSeconds: 10),
            .init(name: "Build", progress: 101, etaSeconds: 10),
            .init(name: "Build", progress: .nan, etaSeconds: 10),
            .init(name: "Build", progress: 10, etaSeconds: -1),
            .init(name: "Build", progress: 10, etaSeconds: .infinity)
        ] { XCTAssertThrowsError(try registry.update(value)) }
        XCTAssertTrue(registry.items.isEmpty)
    }

    func testItemLimitStillAllowsExistingUpdates() throws {
        let registry = ProgressRegistry()
        for i in 0..<50 { try registry.update(.init(name: "Job \(i)", progress: 0, etaSeconds: 10)) }
        XCTAssertThrowsError(try registry.update(.init(name: "Overflow", progress: 0, etaSeconds: 10)))
        XCTAssertNoThrow(try registry.update(.init(name: "Job 0", progress: 50, etaSeconds: 5)))
    }

    func testFragmentedHTTPBodyAndUnicode() throws {
        let body = Data("{\"name\":\"Build 🚀\",\"progress\":42,\"etaSeconds\":30}".utf8)
        var request = Data("POST /items HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        request.append(body.prefix(8))
        XCTAssertNil(try HTTPRequest.parse(request))
        request.append(body.dropFirst(8))
        let parsed = try XCTUnwrap(HTTPRequest.parse(request))
        XCTAssertEqual(parsed.body, body)
        XCTAssertEqual(try JSONDecoder().decode(ProgressUpdate.self, from: parsed.body).name, "Build 🚀")
    }

    func testMalformedAndUnboundedHTTPRequestsAreRejected() {
        for headers in [
            "POST /items HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 6",
            "POST /items HTTP/1.1\r\nTransfer-Encoding: chunked",
            "POST /items HTTP/1.1\r\nContent-Length: -1",
            "POST /items HTTP/1.1\r\nContent-Length: 999999",
            "POST /items HTTP/1.1\r\nContent-Type: application/json",
            "GET /items HTTP/1.1\r\nMalformed"
        ] { XCTAssertThrowsError(try HTTPRequest.parse(Data((headers + "\r\n\r\n").utf8))) }
        XCTAssertThrowsError(try HTTPRequest.parse(Data(repeating: 65, count: 8193)))
    }
}
