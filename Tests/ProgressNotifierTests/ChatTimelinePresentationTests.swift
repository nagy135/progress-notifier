import AppKit
import SwiftUI
import XCTest
import ProgressCore
@testable import ProgressNotifier

final class ChatTimelinePresentationTests: XCTestCase {
    func testCompletionRecallModesAndSelectionUseOneTimeline() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ProgressModel(stateURL: directory.appendingPathComponent("state.json"), completionFeedback: {})
        let parent = UUID(), child = UUID()
        func post(_ name: String, progress: Double, run: UUID? = nil, owner: UUID? = nil) throws -> HTTPResponse {
            let value = ProgressUpdate(name: name, progress: progress, etaSeconds: 60, description: "Progress for \(name)",
                                       t3Thread: .init(environmentId: "mac", threadId: "chat"),
                                       isChild: owner == nil ? nil : true, runId: run, parentRunId: owner)
            let body = try JSONEncoder().encode(value)
            var wire = Data("POST /items HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
            wire.append(body)
            return model.handle(try XCTUnwrap(HTTPRequest.parse(wire)))
        }
        XCTAssertEqual(try post("Old", progress: 0, run: parent).status, 200)
        XCTAssertEqual(try post("Old", progress: 100).status, 200)
        XCTAssertEqual(try post("New", progress: 0).status, 200)
        XCTAssertEqual(try post("Child", progress: 20, run: child, owner: parent).status, 200)
        XCTAssertEqual(model.displayItems.map(\.name), ["Old", "Child", "New"])
        let get = try XCTUnwrap(HTTPRequest.parse(Data("GET /items HTTP/1.1\r\n\r\n".utf8)))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: model.handle(get).body) as? [String: Any])
        let items = try XCTUnwrap(json["items"] as? [[String: Any]])
        let wireChild = try XCTUnwrap(items.first { $0["name"] as? String == "Child" })
        XCTAssertEqual(wireChild["runId"] as? String, child.uuidString)
        XCTAssertEqual(wireChild["parentRunId"] as? String, parent.uuidString)
        XCTAssertNotNil(wireChild["id"])
        XCTAssertNotNil(wireChild["createdAt"])
        let presentation = ProgressPresentation(compact: false)
        func update(_ compact: Bool) {
            presentation.update(items: model.displayItems, compact: compact, animated: false, timeline: model.timelineEntries)
            presentation.measure(Dictionary(uniqueKeysWithValues: model.displayItems.map { ($0.id, CGFloat($0.completing ? 14 : 64)) }), animated: false)
        }
        update(false)
        XCTAssertTrue(presentation.rows[0].receipt)
        XCTAssertLessThan(presentation.rowHeight(presentation.rows[0]), presentation.rowHeight(presentation.rows[2]))
        XCTAssertTrue(presentation.rows[1].timeline?.continuesBelow == true)
        XCTAssertEqual(presentation.focusedItem?.name, "New")
        presentation.focus(try XCTUnwrap(model.displayItems.first?.id), animated: false)
        presentation.moveFocus(by: 1, animated: false)
        let selected = presentation.focusedItemID
        update(true)
        XCTAssertEqual(presentation.focusedItemID, selected)
        XCTAssertEqual(presentation.rows.map(\.item.name), ["Old", "Child", "New"])
        model.clearCompleted()
        update(false)
        XCTAssertEqual(presentation.focusedItemID, selected)
        XCTAssertTrue(presentation.rows.first { $0.id == selected }?.timeline?.detached == true)
        XCTAssertTrue(model.recallCompleted())
        update(false)
        XCTAssertEqual(presentation.focusedItemID, selected)
        XCTAssertEqual(model.displayItems.map(\.name), ["Old", "Child", "New"])
        presentation.focus(try XCTUnwrap(model.displayItems.first?.id), animated: false)
        presentation.setShowsUpdates(true, animated: false)
        XCTAssertFalse(presentation.rows[0].receipt)
        presentation.maximumHeight = 150
        XCTAssertTrue(presentation.needsScrolling)
        XCTAssertEqual(presentation.windowHeight, 150)
    }
    func testNativeTimelineGeometryAcrossModesAndDetailReversals() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ProgressModel(stateURL: directory.appendingPathComponent("state.json"), completionFeedback: {})
        let parent = UUID()
        func post(_ name: String, progress: Double, run: UUID? = nil, owner: UUID? = nil) throws {
            let value = ProgressUpdate(name: name, progress: progress, etaSeconds: 120, project: "progress-notifier",
                                       description: "Checking timeline presentation and child ownership",
                                       t3Thread: .init(environmentId: "mac", threadId: "chat-preview"),
                                       isChild: owner == nil ? nil : true, runId: run, parentRunId: owner)
            let body = try JSONEncoder().encode(value)
            var wire = Data("POST /items HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
            wire.append(body)
            XCTAssertEqual(model.handle(try XCTUnwrap(HTTPRequest.parse(wire))).status, 200)
        }
        for name in ["Link cards to T3 chats", "Add child markers"] {
            try post(name, progress: 0)
            try post(name, progress: 100)
        }
        try post("Group chat followups", progress: 62, run: parent)
        try post("Explore layouts", progress: 80, run: UUID(), owner: parent)
        try post("Review API compatibility", progress: 35, run: UUID(), owner: parent)
        let presentation = ProgressPresentation(compact: false)
        presentation.maximumHeight = 1600
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 370, height: 800),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        let host = ProgressHostingView(rootView: PanelContent {
            ProgressCard(model: model, presentation: presentation,
                         detailsHeightsChanged: { presentation.measure($0, animated: false) },
                         historyHeightsChanged: { presentation.measureHistory($0, animated: false) },
                         toggleUpdates: {}, toggleCompact: {}, openFocusedThread: {}, close: {})
        })
        host.sizingOptions = []
        panel.contentView = host
        func settle(_ compact: Bool, capture: String? = nil) throws {
            presentation.update(items: model.displayItems, compact: compact, animated: false, timeline: model.timelineEntries)
            for _ in 0..<8 {
                panel.setContentSize(CGSize(width: presentation.windowWidth, height: presentation.windowHeight))
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.025))
            }
            XCTAssertEqual(host.bounds.width, presentation.windowWidth, accuracy: 1)
            XCTAssertEqual(host.bounds.height, presentation.windowHeight, accuracy: 1)
            XCTAssertFalse(presentation.needsScrolling)
            XCTAssertEqual(presentation.rows.count, 5)
            XCTAssertTrue(presentation.rows.allSatisfy { $0.detailsHeight > 0 && $0.presence == 1 })
            if let capture, let target = ProcessInfo.processInfo.environment["PROGRESS_NOTIFIER_CAPTURE_DIR"] {
                // Capture after the update pulse settles; geometry assertions above also cover the pulse.
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                let folder = URL(fileURLWithPath: target)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(capture + ".png"))
            }
        }
        try settle(false, capture: "expanded")
        let active = try XCTUnwrap(model.displayItems.first { !$0.completing && !$0.isChild })
        presentation.focus(active.id, animated: false)
        try settle(true, capture: "compact")
        XCTAssertEqual(presentation.focusedItemID, active.id)
        for _ in 0..<3 { try settle(false); try settle(true) }
        presentation.focus(try XCTUnwrap(model.displayItems.first?.id), animated: false)
        presentation.setShowsUpdates(true, animated: false)
        try settle(false, capture: "details")
        XCTAssertFalse(presentation.rows[0].receipt)
        panel.contentView = nil
    }

}
