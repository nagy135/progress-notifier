import AppKit
import XCTest
import QuartzCore
@testable import ProgressNotifier

final class PresentationClockTests: XCTestCase {
    func testVisibleHostClockStopsAndCanReverseWithoutKeepingOldCallbacks() throws {
        guard #available(macOS 14.0, *) else { throw XCTSkip("Native display links require macOS 14") }
        _ = NSApplication.shared
        let panel = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 100, height: 100),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        panel.contentView = host
        panel.orderFrontRegardless()
        let clock = PresentationClock()
        defer { clock.stop(); panel.orderOut(nil); panel.contentView = nil }

        let initial = expectation(description: "Visible host receives display frames")
        var timestamps: [TimeInterval] = []
        clock.start(view: host) { timestamp in
            timestamps.append(timestamp)
            if timestamps.count == 3 { initial.fulfill() }
            return true
        }
        wait(for: [initial], timeout: 2)
        XCTAssertTrue(zip(timestamps, timestamps.dropFirst()).allSatisfy { $0 < $1 })
        let oldCount = timestamps.count

        let reversed = expectation(description: "Replacement clock finishes")
        var replacementCount = 0
        clock.start(view: host) { _ in
            replacementCount += 1
            if replacementCount == 3 { reversed.fulfill(); return false }
            return true
        }
        wait(for: [reversed], timeout: 2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        XCTAssertEqual(timestamps.count, oldCount, "Reversals must cancel the previous clock")
        XCTAssertEqual(replacementCount, 3, "A settled transition must stop requesting frames")
    }

    func testUnhostedClockCanBeCancelledBeforeItsFirstTick() {
        let clock = PresentationClock()
        var ticks = 0
        clock.start(view: nil) { _ in ticks += 1; return true }
        clock.stop()
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        XCTAssertEqual(ticks, 0)
    }
}
