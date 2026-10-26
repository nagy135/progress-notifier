import AppKit
import SwiftUI

enum PanelPlacement: String {
    case topRight
    case bottomRight

    var contentAlignment: Alignment { self == .topRight ? .topTrailing : .bottomTrailing }
    var toggled: Self { self == .topRight ? .bottomRight : .topRight }

    func frame(resizing previous: CGRect, to size: CGSize, in visibleFrame: CGRect,
               reposition: Bool) -> CGRect {
        let x = (reposition ? visibleFrame.maxX - 6 : previous.maxX) - size.width
        let y: CGFloat
        if reposition {
            y = self == .topRight ? visibleFrame.maxY - size.height - 6 : visibleFrame.minY + 6
        } else {
            y = self == .topRight ? previous.maxY - size.height : previous.minY
        }
        return CGRect(x: x,
                      y: min(max(visibleFrame.minY, y), max(visibleFrame.minY, visibleFrame.maxY - size.height)),
                      width: size.width, height: size.height)
    }
}
