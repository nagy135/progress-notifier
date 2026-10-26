import XCTest
@testable import ProgressCore

final class ProgressCoreTests: XCTestCase {
    func testHistoryRecallsOneAtATimeNewestFirstAndClearResetsIt() throws {
        let registry = ProgressRegistry()
        let older = try finish("Older", in: registry)
        let newer = try finish("Newer", in: registry)
        try registry.update(.init(name: "Running", progress: 20, etaSeconds: 60))
        registry.clearCompleted()

        XCTAssertTrue(registry.revealedHistory.isEmpty)
        XCTAssertTrue(registry.revealNextCompleted())
        XCTAssertEqual(registry.revealedHistory.map(\.id), [newer])
        XCTAssertTrue(registry.revealNextCompleted())
        XCTAssertEqual(registry.revealedHistory.map(\.id), [newer, older])
        XCTAssertFalse(registry.revealNextCompleted())

        registry.clearCompleted()
        XCTAssertTrue(registry.revealedHistory.isEmpty)
        XCTAssertEqual(registry.items.map(\.name), ["Running"])
        XCTAssertEqual(registry.history.count, 2)
        XCTAssertTrue(registry.revealNextCompleted())
        XCTAssertEqual(registry.revealedHistory.map(\.id), [newer])
        XCTAssertTrue(registry.revealNextCompleted())
        XCTAssertEqual(registry.revealedHistory.map(\.id), [newer, older])
    }

    func testCompletionIsArchivedImmediatelyAndRestoredOnlyOnRecall() throws {
        let registry = ProgressRegistry()
        let start = Date(timeIntervalSince1970: 1000)
        let end = start.addingTimeInterval(47)
        let icon = ProjectIcon(kind: .emoji, emoji: "🎹")
        try registry.update(.init(name: "Build", progress: 10, etaSeconds: 60, project: "Project", projectIcon: icon), now: start)
        XCTAssertTrue(try registry.update(.init(name: "Build", progress: 100, etaSeconds: 0), now: end))
        XCTAssertFalse(try registry.update(.init(name: "Build", progress: 100, etaSeconds: 0), now: end))
        XCTAssertEqual(registry.history.count, 1)
        XCTAssertFalse(registry.revealNextCompleted(), "A finishing card must not appear twice")

        let data = try JSONEncoder().encode(registry.snapshot)
        let restored = ProgressRegistry(snapshot: try JSONDecoder().decode(ProgressSnapshot.self, from: data))
        XCTAssertTrue(restored.items.isEmpty)
        XCTAssertTrue(restored.revealedHistory.isEmpty)
        XCTAssertTrue(restored.revealNextCompleted())
        let result = try XCTUnwrap(restored.revealedHistory.first)
        XCTAssertEqual(result.id, registry.items[0].id)
        XCTAssertEqual(result.createdAt, start)
        XCTAssertEqual(result.completedAt, end)
        XCTAssertEqual(result.project, "Project")
        XCTAssertEqual(result.projectIcon, icon)
        XCTAssertEqual(result.progress, 100)

        let relaunched = ProgressRegistry(snapshot: restored.snapshot)
        XCTAssertTrue(relaunched.revealedHistory.isEmpty)
        XCTAssertTrue(relaunched.revealNextCompleted())
        XCTAssertEqual(relaunched.revealedHistory[0].id, result.id)
    }

    func testClearDuringCompletionAllowsRecallThatSurvivesDelayedRemoval() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: "Build", progress: 10, etaSeconds: 60))
        try registry.update(.init(name: "Build", progress: 100, etaSeconds: 0))
        let id = registry.items[0].id
        registry.clearCompleted()
        XCTAssertTrue(registry.items.isEmpty)
        XCTAssertTrue(registry.revealNextCompleted())
        registry.removeCompleted(id: id) // The original 1.25-second callback.
        XCTAssertEqual(registry.revealedHistory.map(\.id), [id])
    }

    func testDeletingRecalledResultSuppressesItsNameUntilUndoWithoutRemovingNewRun() throws {
        let registry = ProgressRegistry()
        let older = try finish("Build", in: registry)
        let newer = try finish("Build", in: registry)
        registry.clearCompleted()
        try registry.update(.init(name: "Build", progress: 10, etaSeconds: 60))
        let runningID = registry.items[0].id
        XCTAssertTrue(registry.revealNextCompleted())
        XCTAssertEqual(registry.revealedHistory.map(\.id), [newer])

        registry.dismiss(id: newer)
        XCTAssertEqual(registry.items.map(\.id), [runningID])
        try registry.update(.init(name: "Build", progress: 20, etaSeconds: 40))
        XCTAssertEqual(registry.items[0].progress, 10)
        XCTAssertTrue(registry.revealNextCompleted())
        XCTAssertEqual(registry.revealedHistory.map(\.id), [older])
        XCTAssertFalse(registry.revealNextCompleted())
        registry.clearCompleted()
        XCTAssertTrue(registry.revealNextCompleted())
        XCTAssertEqual(registry.revealedHistory.map(\.id), [older])
        XCTAssertTrue(registry.undoDeletion())
        XCTAssertEqual(registry.revealedHistory.map(\.id), [newer, older])
        try registry.update(.init(name: "Build", progress: 20, etaSeconds: 40))
        XCTAssertEqual(registry.items[0].progress, 20)
    }

    func testNewCompletionsAppearAutomaticallyWithoutRepeatingOnRecall() throws {
        let registry = ProgressRegistry()
        let older = try finish("Older", in: registry)
        XCTAssertEqual(registry.revealedHistory.map(\.id), [older])
        XCTAssertFalse(registry.revealNextCompleted())
        let newer = try finish("Newer", in: registry)
        XCTAssertEqual(registry.revealedHistory.map(\.id), [newer, older])
        XCTAssertFalse(registry.revealNextCompleted())
        registry.clearCompleted()
        XCTAssertTrue(registry.revealNextCompleted())
        XCTAssertEqual(registry.revealedHistory.map(\.id), [newer])
    }

    func testHistoryIsBoundedAndDoesNotUseActiveItemCapacity() throws {
        let registry = ProgressRegistry()
        var newest: UUID?
        for index in 0...ProgressRegistry.historyLimit {
            newest = try finish("Done \(index)", in: registry)
        }
        XCTAssertEqual(registry.history.count, ProgressRegistry.historyLimit)
        XCTAssertEqual(registry.history.first?.id, newest)
        for index in 0..<50 {
            try registry.update(.init(name: "Running \(index)", progress: 10, etaSeconds: 60))
        }
        XCTAssertFalse(registry.revealNextCompleted())
        XCTAssertEqual(registry.revealedHistory.first?.id, newest)
        XCTAssertEqual(registry.items.count, 50)
        XCTAssertThrowsError(try registry.update(.init(name: "Overflow", progress: 10, etaSeconds: 60)))
        registry.clearCompleted()
        XCTAssertEqual(registry.items.count, 50)
        XCTAssertTrue(registry.revealNextCompleted())
        XCTAssertEqual(registry.revealedHistory.first?.id, newest)
    }

    private func finish(_ name: String, in registry: ProgressRegistry) throws -> UUID {
        try registry.update(.init(name: name, progress: 10, etaSeconds: 60))
        try registry.update(.init(name: name, progress: 100, etaSeconds: 0))
        let id = try XCTUnwrap(registry.items.first(where: { $0.name == name })?.id)
        registry.removeCompleted(id: id)
        return id
    }

    func testFirstAddedDateSurvivesUpdatesAndRelaunchAndResetsForNewRun() throws {
        let registry = ProgressRegistry()
        let start = Date(timeIntervalSince1970: 1000)
        try registry.update(.init(name: "Build", progress: 10, etaSeconds: 60), now: start)
        try registry.update(.init(name: "Build", progress: 20, etaSeconds: 30), now: start.addingTimeInterval(47))
        XCTAssertEqual(registry.items[0].createdAt, start)

        let data = try JSONEncoder().encode(registry.snapshot)
        let restored = ProgressRegistry(snapshot: try JSONDecoder().decode(ProgressSnapshot.self, from: data))
        try restored.update(.init(name: "Build", progress: 30, etaSeconds: 20), now: start.addingTimeInterval(300))
        XCTAssertEqual(restored.items[0].createdAt, start)

        try restored.update(.init(name: "Build", progress: 100, etaSeconds: 0), now: start.addingTimeInterval(400))
        XCTAssertEqual(restored.items[0].createdAt, start)
        restored.removeCompleted(id: restored.items[0].id)
        let nextStart = start.addingTimeInterval(500)
        try restored.update(.init(name: "Build", progress: 0, etaSeconds: 60), now: nextStart)
        XCTAssertEqual(restored.items[0].createdAt, nextStart)
    }

    func testProjectMetadataSurvivesUpdatesAndSnapshot() throws {
        let registry = ProgressRegistry()
        let icon = ProjectIcon(kind: .lucide, name: "snowflake", color: "blue")
        try registry.update(.init(name: "Build", progress: 10, etaSeconds: 60, project: " nix-darwin ", projectIcon: icon))
        let id = registry.items[0].id
        try registry.update(.init(name: "Build", progress: 20, etaSeconds: 30))
        XCTAssertEqual(registry.items[0].project, "nix-darwin")
        XCTAssertEqual(registry.items[0].projectIcon, icon)
        let data = try JSONEncoder().encode(registry.snapshot)
        let restored = ProgressRegistry(snapshot: try JSONDecoder().decode(ProgressSnapshot.self, from: data))
        XCTAssertEqual(restored.items[0].id, id)
        XCTAssertEqual(restored.items[0].projectIcon, icon)
        try restored.update(.init(name: "Build", progress: 30, etaSeconds: 20, project: ""))
        XCTAssertNil(restored.items[0].project)
        XCTAssertNil(restored.items[0].projectIcon)
    }

    func testLegacyJSONAndSnapshotsRemainCompatible() throws {
        let update = try JSONDecoder().decode(ProgressUpdate.self, from: Data(#"{"name":"Build","progress":10,"etaSeconds":30}"#.utf8))
        XCTAssertNil(update.project)
        XCTAssertNil(update.projectIcon)
        let snapshot = #"{"items":[{"id":"0A201158-069C-4E7B-A850-D7D2AC46F548","name":"Build","progress":10,"expectedFinish":1000,"completing":false}],"dismissed":[]}"#
        let registry = ProgressRegistry(snapshot: try JSONDecoder().decode(ProgressSnapshot.self, from: Data(snapshot.utf8)))
        XCTAssertEqual(registry.items.count, 1)
        XCTAssertNil(registry.items[0].project)
        XCTAssertNil(registry.items[0].createdAt)
        XCTAssertTrue(registry.history.isEmpty)
        try registry.update(.init(name: "Build", progress: 20, etaSeconds: 30))
        XCTAssertNil(registry.items[0].createdAt)
    }

    func testT3IconsAndDefaultMonograms() throws {
        for icon in [ProjectIcon(kind: .emoji, emoji: "🎹"),
                     .init(kind: .monogram, color: "violet", text: "PN"),
                     .init(kind: .lucide, name: "message-square-dashed", color: "gray")] {
            XCTAssertEqual(try icon.validated(), icon)
        }
        XCTAssertEqual(ProjectIcon.defaultIcon(for: "progress-notifier").text, "PN")
        XCTAssertEqual(ProjectIcon.defaultIcon(for: "t3-code").text, "T3")
        XCTAssertEqual(ProjectIcon.defaultIcon(for: "API").text, "AI")
        XCTAssertEqual(ProjectIcon.defaultIcon(for: "!!!").text, "PR")
        XCTAssertEqual(ProjectIcon.defaultIcon(for: " Progress-Notifier "), ProjectIcon.defaultIcon(for: "progress-notifier"))
    }

    func testInvalidMetadataIsRejectedWithoutMutation() throws {
        let registry = ProgressRegistry()
        for value in [ProgressUpdate(name: "Build", progress: 10, etaSeconds: 30, project: "a\nb"),
                      .init(name: "Build", progress: 10, etaSeconds: 30, project: String(repeating: "a", count: 161)),
                      .init(name: "Build", progress: 10, etaSeconds: 30, projectIcon: .init(kind: .lucide, name: "../file", color: "blue")),
                      .init(name: "Build", progress: 10, etaSeconds: 30, projectIcon: .init(kind: .monogram, color: "invalid", text: "PN")),
                      .init(name: "Build", progress: 10, etaSeconds: 30, projectIcon: .init(kind: .emoji, emoji: ""))] {
            XCTAssertThrowsError(try registry.update(value))
        }
        XCTAssertTrue(registry.items.isEmpty)
    }

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
        XCTAssertEqual(restored.items.count, 1)
        XCTAssertTrue(restored.undoDeletion())
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

    func testDismissalKeepsUpdatesSilentUntilUndo() throws {
        let registry = ProgressRegistry()
        try registry.update(.init(name: " Build ", progress: 10, etaSeconds: 30))
        registry.dismiss(name: "Build")
        try registry.update(.init(name: "Build", progress: 50, etaSeconds: 10))
        XCTAssertTrue(registry.items.isEmpty)
        try registry.update(.init(name: "Build", progress: 100, etaSeconds: 0))
        XCTAssertTrue(registry.items.isEmpty)
        XCTAssertTrue(registry.history.isEmpty)
        try registry.update(.init(name: "Build", progress: 0, etaSeconds: 30))
        XCTAssertTrue(registry.items.isEmpty)
        XCTAssertTrue(registry.undoDeletion())
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
