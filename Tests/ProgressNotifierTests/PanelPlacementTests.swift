import AppKit
import XCTest
@testable import ProgressNotifier

final class PanelPlacementTests: XCTestCase {
    // An offset display with a Dock/menu-bar inset catches assumptions about screen zero.
    private let screen = CGRect(x: -1600, y: 80, width: 1600, height: 900)

    func testSwitchingCornersSnapsDraggedPanelToScreenEdges() {
        let dragged = CGRect(x: -900, y: 400, width: 220, height: 180)
        let bottom = PanelPlacement.topRight.toggled.frame(resizing: dragged, to: dragged.size,
                                                          in: screen, reposition: true)
        XCTAssertEqual(bottom, CGRect(x: -226, y: 86, width: 220, height: 180))
        let top = PanelPlacement.bottomRight.toggled.frame(resizing: bottom, to: bottom.size,
                                                          in: screen, reposition: true)
        XCTAssertEqual(top, CGRect(x: -226, y: 794, width: 220, height: 180))
    }

    func testGrowthAndShrinkageKeepTheChosenCornerFixed() {
        for placement in [PanelPlacement.topRight, .bottomRight] {
            var frame = placement.frame(resizing: .zero, to: CGSize(width: 92, height: 56),
                                        in: screen, reposition: true)
            let cornerY = placement == .topRight ? frame.maxY : frame.minY
            for size in [CGSize(width: 370, height: 300), CGSize(width: 370, height: 852),
                         CGSize(width: 220, height: 100), CGSize(width: 92, height: 56)] {
                frame = placement.frame(resizing: frame, to: size, in: screen, reposition: false)
                XCTAssertEqual(frame.maxX, screen.maxX - 6)
                XCTAssertEqual(placement == .topRight ? frame.maxY : frame.minY, cornerY)
                XCTAssertTrue(screen.contains(frame))
            }
        }
    }

    func testDraggedPanelStaysInsideScreenWhenGrowing() {
        let bottom = PanelPlacement.bottomRight.frame(resizing: CGRect(x: -400, y: 900, width: 220, height: 56),
                                                      to: CGSize(width: 370, height: 500), in: screen, reposition: false)
        XCTAssertEqual(bottom.maxY, screen.maxY)
        let top = PanelPlacement.topRight.frame(resizing: CGRect(x: -400, y: 100, width: 220, height: 56),
                                                to: CGSize(width: 370, height: 500), in: screen, reposition: false)
        XCTAssertEqual(top.minY, screen.minY)
    }
}
