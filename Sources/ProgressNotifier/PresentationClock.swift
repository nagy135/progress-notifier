import AppKit
import QuartzCore

/// Drive geometry on the panel's display, including variable refresh rate screens.
/// The timer is only for macOS 13 and presentations without a visible native host.
final class PresentationClock {
    private var cancel: (() -> Void)?

    deinit { stop() }

    func stop() {
        cancel?()
        cancel = nil
    }

    func start(view: NSView?, tick: @escaping (TimeInterval) -> Bool) {
        stop()
        if #available(macOS 14.0, *), let view, view.window?.isVisible == true {
            let target = DisplayLinkTarget(tick: tick)
            let link = view.displayLink(target: target, selector: #selector(DisplayLinkTarget.advance(_:)))
            let rate = Float(view.window?.screen?.maximumFramesPerSecond ?? 60)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, rate), maximum: rate, preferred: rate)
            cancel = { link.invalidate() }
            link.add(to: .main, forMode: .common)
        } else {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { timer in
                if !tick(CACurrentMediaTime()) { timer.invalidate() }
            }
            cancel = { timer.invalidate() }
            RunLoop.main.add(timer, forMode: .common)
        }
    }
}

@available(macOS 14.0, *)
private final class DisplayLinkTarget: NSObject {
    let tick: (TimeInterval) -> Bool

    init(tick: @escaping (TimeInterval) -> Bool) { self.tick = tick }

    @objc func advance(_ link: CADisplayLink) {
        // Calculate geometry for the frame being presented, rather than the last one.
        if !tick(link.targetTimestamp) { link.invalidate() }
    }
}
