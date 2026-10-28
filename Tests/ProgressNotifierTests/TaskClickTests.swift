import AppKit
import SwiftUI
import XCTest
import ProgressCore
@testable import ProgressNotifier

final class TaskClickTests: XCTestCase {
    func testClickSelectsAndDoubleClickOpensClickedTaskInBothModes() throws {
        for compact in [false, true] {
            let fixture = try Fixture(compact: compact)
            defer { fixture.close() }
            XCTAssertTrue(fixture.host.acceptsFirstMouse(for: nil))
            fixture.click(row: 1)
            XCTAssertEqual(fixture.presentation.focusedItemID, fixture.items[1].id)
            XCTAssertTrue(fixture.opened.isEmpty)
            XCTAssertEqual(fixture.modeToggles, 0)

            // Double-click a different task directly, without selecting it first.
            fixture.panel.resignKey()
            XCTAssertFalse(fixture.panel.isKeyWindow)
            fixture.click(row: 0)
            fixture.click(row: 0, count: 2)
            XCTAssertTrue(fixture.panel.isKeyWindow)
            XCTAssertEqual(fixture.presentation.focusedItemID, fixture.items[0].id)
            XCTAssertEqual(fixture.opened, [try XCTUnwrap(fixture.items[0].t3Thread?.url)])
            XCTAssertEqual(fixture.modeToggles, 0)

            fixture.click(row: 2)
            fixture.click(row: 2, count: 2)
            XCTAssertEqual(fixture.presentation.focusedItemID, fixture.items[2].id, "compact=\(compact)")
            XCTAssertEqual(fixture.opened.count, 1, "Unlinked tasks should only be selected")
            XCTAssertEqual(fixture.modeToggles, 0)
        }
    }

    func testCloseButtonDoesNotSelectOpenOrToggleModeAndBackgroundStillToggles() throws {
        let fixture = try Fixture(compact: false)
        defer { fixture.close() }
        fixture.click(row: 1, closeButton: true)
        XCTAssertEqual(fixture.model.displayItems.map(\.id), [fixture.items[0].id, fixture.items[2].id])
        XCTAssertEqual(fixture.presentation.focusedItemID, fixture.items[0].id)
        XCTAssertTrue(fixture.opened.isEmpty)
        XCTAssertEqual(fixture.modeToggles, 0)
        fixture.click(at: CGPoint(x: 70, y: 30))
        XCTAssertEqual(fixture.modeToggles, 1)
    }

    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model: ProgressModel
        let presentation: ProgressPresentation
        let panel: ProgressPanel
        let host: ProgressHostingView<PanelContent<ProgressCard>>
        let items: [ProgressItem]
        var opened: [URL] = []
        var modeToggles = 0
        private var timestamp = ProcessInfo.processInfo.systemUptime

        init(compact: Bool) throws {
            _ = NSApplication.shared
            let registry = ProgressRegistry()
            for (index, name) in ["First", "Second", "Unlinked"].enumerated() {
                try registry.update(.init(name: name, progress: 25, etaSeconds: 60,
                    t3Thread: index < 2 ? .init(environmentId: "mac", threadId: name) : nil))
            }
            items = registry.items
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stateURL = directory.appendingPathComponent("state.json")
            try JSONEncoder().encode(registry.snapshot).write(to: stateURL)
            model = ProgressModel(stateURL: stateURL)
            presentation = ProgressPresentation(compact: compact)
            presentation.update(items: model.displayItems, compact: compact, animated: false)
            // Install callbacks after initialization so they can capture the fixture.
            host = ProgressHostingView(rootView: PanelContent { [model, presentation] in
                ProgressCard(model: model, presentation: presentation,
                    detailsHeightsChanged: { _ in }, historyHeightsChanged: { _ in },
                    toggleUpdates: {}, toggleCompact: {}, openFocusedThread: {}, close: {})
            })
            panel = ProgressPanel(contentRect: CGRect(x: 100, y: 100, width: presentation.windowWidth,
                                               height: presentation.windowHeight),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            host.rootView = PanelContent {
                ProgressCard(model: model, presentation: presentation,
                    detailsHeightsChanged: { [weak self] in self?.presentation.measure($0, animated: false) },
                    historyHeightsChanged: { [weak self] in self?.presentation.measureHistory($0, animated: false) },
                    toggleUpdates: {}, toggleCompact: { [weak self] in self?.modeToggles += 1 },
                    openFocusedThread: { [weak self] in
                        guard let self else { return }
                        T3ThreadOpener { [weak self] urls, _, _ in self?.opened += urls }
                            .open(self.presentation.focusedItem?.t3Thread)
                    }, close: {})
            }
            host.sizingOptions = []
            panel.contentView = host
            panel.orderFrontRegardless()
            settle()
            panel.setContentSize(CGSize(width: presentation.windowWidth, height: presentation.windowHeight))
            settle()
        }

        func click(row index: Int, count: Int = 1, closeButton: Bool = false) {
            let expansion = presentation.expansion
            var top = 10 + ProgressCard.verticalInset(expansion: expansion) + 32 * expansion + 4 * expansion
            for previous in 0..<index {
                top += presentation.rowHeight(presentation.rows[previous]) + presentation.spacing(before: previous + 1)
            }
            let x = closeButton
                ? 10 + ProgressCard.horizontalInset(expansion: expansion) + 4 * expansion + ProgressCard.expandedRowWidth - 23
                : 10 + ProgressCard.horizontalInset(expansion: expansion) + 4 * expansion + 50
            let y = top + (closeButton ? 20 : presentation.rowHeight(presentation.rows[index]) / 2)
            click(at: CGPoint(x: x, y: y), count: count)
        }

        func click(at point: CGPoint, count: Int = 1) {
            let location = host.convert(point, to: nil)
            for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                timestamp += 0.01
                let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: timestamp,
                    windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
                panel.sendEvent(event)
            }
            settle()
        }

        private func settle() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        func close() {
            panel.orderOut(nil)
            panel.contentView = nil
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
