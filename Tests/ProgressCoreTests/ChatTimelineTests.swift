import XCTest
@testable import ProgressCore

final class ChatTimelineTests: XCTestCase {
    func testInterleavedChatsAndLateChildKeepCreationOrderAndOwningRun() throws {
        let registry = ProgressRegistry()
        let a = T3ThreadReference(environmentId: "mac", threadId: "a")
        let b = T3ThreadReference(environmentId: "mac", threadId: "b")
        let parent = UUID(), child = UUID(), newer = UUID()
        let start = Date(timeIntervalSince1970: 100)
        try registry.update(.init(name: "Old", progress: 0, etaSeconds: 60, t3Thread: a, runId: parent), now: start)
        try registry.update(.init(name: "Other", progress: 0, etaSeconds: 60, t3Thread: b), now: start.addingTimeInterval(1))
        try registry.update(.init(name: "New", progress: 0, etaSeconds: 60, t3Thread: a, runId: newer), now: start.addingTimeInterval(2))
        try registry.update(.init(name: "Late child", progress: 0, etaSeconds: 60, t3Thread: a, isChild: true,
                                  runId: child, parentRunId: parent), now: start.addingTimeInterval(3))
        try registry.update(.init(name: "Old", progress: 100, etaSeconds: 0), now: start.addingTimeInterval(4))
        let visible = registry.visibleItems.filter { !$0.completing } + registry.revealedHistory
        let rows = ChatTimeline.entries(visible: visible, retained: registry.items + registry.history)
        XCTAssertEqual(rows.map(\.item.name), ["Old", "Late child", "New", "Other"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 0, 0])
        XCTAssertEqual(rows.map(\.continuesBelow), [false, true, false, false])
        XCTAssertEqual(rows.map(\.startsGroup), [true, false, false, true])
        XCTAssertEqual(rows[1].parentLabel, "Old")
        registry.clearCompleted()
        let hidden = ChatTimeline.entries(visible: registry.visibleItems, retained: registry.items + registry.history)
        XCTAssertEqual(hidden.map(\.item.name), ["New", "Late child", "Other"])
        XCTAssertTrue(hidden[1].detached)
        XCTAssertEqual(hidden[1].parentLabel, "Parent not visible")
        XCTAssertTrue(registry.revealNextCompleted())
        XCTAssertEqual(ChatTimeline.entries(visible: registry.visibleItems + registry.revealedHistory,
                                            retained: registry.items + registry.history).map(\.item.name), rows.map(\.item.name))
    }

    func testSameProjectDifferentEnvironmentUnlinkedAndLegacyChildrenAreSeparate() throws {
        let registry = ProgressRegistry()
        let a = T3ThreadReference(environmentId: "mac", threadId: "chat")
        for (name, destination, child) in [("Main", a, false), ("Legacy child", a, true),
                                          ("Remote", T3ThreadReference(environmentId: "remote", threadId: "chat"), false),
                                          ("Unlinked", nil, false)] {
            try registry.update(.init(name: name, progress: 0, etaSeconds: 60, project: "Same project",
                                      t3Thread: destination, isChild: child))
        }
        let rows = ChatTimeline.entries(visible: registry.items)
        XCTAssertEqual(rows.map(\.startsGroup), [true, false, true, false])
        XCTAssertTrue(rows[1].detached)
        XCTAssertEqual(rows[1].parentLabel, "Parent unspecified")
        XCTAssertFalse(rows[3].startsGroup)
    }

    func testEqualDatesUsePersistedCreationOrderAcrossHistoryAndRelaunch() throws {
        let registry = ProgressRegistry()
        let chat = T3ThreadReference(environmentId: "mac", threadId: "chat")
        let date = Date(timeIntervalSince1970: 100)
        for name in ["First", "Second", "Third"] {
            try registry.update(.init(name: name, progress: 0, etaSeconds: 60, t3Thread: chat), now: date)
            try registry.update(.init(name: name, progress: 100, etaSeconds: 0), now: date)
        }
        let restored = ProgressRegistry(snapshot: try JSONDecoder().decode(ProgressSnapshot.self, from: JSONEncoder().encode(registry.snapshot)))
        XCTAssertTrue(restored.revealNextCompleted())
        XCTAssertTrue(restored.revealNextCompleted())
        XCTAssertTrue(restored.revealNextCompleted())
        XCTAssertEqual(ChatTimeline.entries(visible: restored.revealedHistory).map(\.item.name), ["First", "Second", "Third"])
    }
}
