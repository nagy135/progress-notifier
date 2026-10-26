import AppKit
import XCTest
@testable import ProgressNotifier

private final class FocusObserver: NSObject, NSWindowDelegate {
    var focused = false
    func windowDidBecomeKey(_ notification: Notification) { focused = true }
    func windowDidResignKey(_ notification: Notification) { focused = false }
}

final class PanelFocusTests: XCTestCase {
    func testReleasingFocusClearsKeyboardRoutingAndCanBeFocusedAgain() {
        _ = NSApplication.shared
        let panel = ProgressPanel(contentRect: CGRect(x: 100, y: 100, width: 220, height: 60),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let observer = FocusObserver()
        panel.delegate = observer
        defer { panel.orderOut(nil) }

        for _ in 0..<3 {
            panel.makeKeyAndOrderFront(nil)
            XCTAssertTrue(panel.isKeyWindow)
            XCTAssertTrue(NSApp.keyWindow === panel)
            XCTAssertTrue(observer.focused)

            let frame = panel.frame
            panel.releaseKeyboardFocus()
            XCTAssertTrue(panel.isVisible)
            XCTAssertEqual(panel.frame, frame)
            XCTAssertFalse(panel.isKeyWindow)
            XCTAssertFalse(NSApp.keyWindow === panel, "Escape must release keyboard routing as well as the border")
            XCTAssertFalse(observer.focused)

            panel.orderFrontRegardless()
            XCTAssertFalse(panel.isKeyWindow, "Background refresh must not restore keyboard focus")
            XCTAssertFalse(NSApp.keyWindow === panel)
        }
    }
}
