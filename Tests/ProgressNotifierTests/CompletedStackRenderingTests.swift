import AppKit
import SwiftUI
import XCTest
import ProgressCore
@testable import ProgressNotifier

final class CompletedStackRenderingTests: XCTestCase {
    func testStaticCardsHaveNoRepeatingClockAndLiveCardsKeepTheirCadence() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(Array(CardTimelineSchedule(interval: 1, paused: true).entries(from: start, mode: .normal)), [start])
        for interval: TimeInterval in [1, 60] {
            let dates = Array(CardTimelineSchedule(interval: interval, paused: false)
                .entries(from: start, mode: .normal).prefix(3))
            XCTAssertEqual(dates, [start, start.addingTimeInterval(interval), start.addingTimeInterval(interval * 2)])
        }
    }

    func testLargeCompletedStackOnlyBuildsHistoryWhenOpened() throws {
        _ = NSApplication.shared
        let registry = ProgressRegistry()
        for index in 0..<40 {
            for step in 0..<50 {
                try registry.update(.init(name: "Completed task \(index)", progress: Double(step), etaSeconds: 60,
                                          description: "Update \(step) with enough text to wrap onto another line in the card"))
            }
            try registry.update(.init(name: "Completed task \(index)", progress: 100, etaSeconds: 0,
                                      description: "Finished"))
        }
        let items = registry.history
        XCTAssertEqual(items.count, 40)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ProgressModel(stateURL: directory.appendingPathComponent("state.json"))
        let presentation = ProgressPresentation(compact: false)
        presentation.maximumHeight = 600
        presentation.update(items: items, compact: false, animated: false)
        var mountedHistories: [UUID: CGFloat] = [:]
        let host = ProgressHostingView(rootView: PanelContent {
            ProgressCard(model: model, presentation: presentation,
                         detailsHeightsChanged: { presentation.measure($0, animated: false) },
                         historyHeightsChanged: {
                             mountedHistories = $0
                             presentation.measureHistory($0, animated: false)
                         }, toggleUpdates: {}, toggleCompact: {}, openFocusedThread: {}, close: {})
        })
        host.sizingOptions = []
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 390, height: 600),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.contentView = host
        defer { panel.contentView = nil }
        func settle() {
            for _ in 0..<6 {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.025))
            }
        }
        let start = Date()
        settle()
        print("40 completed cards, 2,000 folded updates: \(Date().timeIntervalSince(start))s to settle")
        XCTAssertTrue(mountedHistories.isEmpty, "Folded histories must not create snapshot rows")
        XCTAssertTrue(presentation.needsScrolling)
        XCTAssertTrue(presentation.rows.allSatisfy { $0.detailsHeight > 0 })

        presentation.setShowsUpdates(true, animated: false)
        settle()
        let first = try XCTUnwrap(presentation.focusedItemID)
        XCTAssertEqual(Set(mountedHistories.keys), [first])
        XCTAssertGreaterThan(presentation.rows.first { $0.id == first }?.historyHeight ?? 0, 0)
        presentation.moveFocus(by: 1, animated: false)
        settle()
        XCTAssertEqual(Set(mountedHistories.keys), [try XCTUnwrap(presentation.focusedItemID)])
        presentation.setShowsUpdates(false, animated: false)
        settle()
        XCTAssertTrue(mountedHistories.isEmpty)
        XCTAssertTrue(presentation.rows.allSatisfy { $0.historyHeight == 0 })
    }
}
