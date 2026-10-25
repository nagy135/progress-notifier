import AppKit
import SwiftUI
import XCTest
@testable import ProgressNotifier

private struct ProbeFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private final class ProbeSize: ObservableObject {
    @Published var size = CGSize(width: 370, height: 180)
}

private struct ContentProbe: View {
    @ObservedObject var state: ProbeSize
    let measured: (CGRect) -> Void

    var body: some View {
        Color.clear.frame(width: state.size.width, height: state.size.height)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ProbeFrameKey.self, value: proxy.frame(in: .global))
            })
            .onPreferenceChange(ProbeFrameKey.self, perform: measured)
    }
}

final class PanelContentTests: XCTestCase {
    func testContentStaysAtTopRightWhileNativeWindowRoundsFractionalSizes() {
        _ = NSApplication.shared
        let panel = NSPanel(contentRect: CGRect(x: 800, y: 800, width: 370, height: 180),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let state = ProbeSize()
        var contentFrame = CGRect.zero
        let host = NSHostingView(rootView: PanelContent {
            ContentProbe(state: state) { contentFrame = $0 }
        })
        host.sizingOptions = []
        panel.contentView = host
        let topRight = CGPoint(x: panel.frame.maxX, y: panel.frame.maxY)

        // Exercise growth, shrinkage, and width changes, across AppKit's rounding boundaries.
        for offset in [0.1, 0.35, 0.6, 0.9, 1.15, 1.4, 1.65, 2.0, 1.9, 1.1, 0.5, 0.0] {
            state.size = CGSize(width: 370 + offset, height: 180 + offset)
            panel.setFrame(CGRect(x: topRight.x - state.size.width, y: topRight.y - state.size.height,
                                  width: state.size.width, height: state.size.height), display: false)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))

            XCTAssertEqual(contentFrame.minY, 0, accuracy: 0.001, "Top edge moved at offset \(offset)")
            XCTAssertEqual(contentFrame.maxX, host.bounds.maxX, accuracy: 0.001)
            XCTAssertEqual(panel.frame.maxY, topRight.y, accuracy: 0.001)
            XCTAssertEqual(panel.frame.maxX, topRight.x, accuracy: 0.001)
        }
        panel.contentView = nil
    }
}
