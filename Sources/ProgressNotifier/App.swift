import AppKit
import SwiftUI

private final class ProgressPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = ProgressModel()
    private let server = HTTPServer()
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private var statusLine: NSMenuItem?
    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Progress Notifier")
        let menu = NSMenu()
        let line = NSMenuItem(title: "Starting local API…", action: nil, keyEquivalent: "")
        menu.addItem(line)
        menu.addItem(.separator())
        let show = NSMenuItem(title: "Show Progress", action: #selector(showProgress), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(withTitle: "Quit Progress Notifier", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        statusLine = line

        let panel = ProgressPanel(contentRect: NSRect(x: 0, y: 0, width: 370, height: 200),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Progress Notifier"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel
        model.changed = { [weak self] in self?.refreshPanel() }
        server.handle = { [weak self] request in
            self?.model.handle(request) ?? HTTPResponse(500, ["error": "App unavailable"])
        }
        server.stateChanged = { [weak self] error in
            if let error { self?.fail(error) }
            else { self?.statusLine?.title = "Listening on 127.0.0.1:8766" }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            self?.refreshPanel(reposition: true)
        }
        do { try server.start() } catch { fail(error.localizedDescription) }
    }

    private func fail(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Progress Notifier could not start"
        alert.informativeText = "Could not listen on 127.0.0.1:8766. Another instance or app may be using the port.\n\n\(message)"
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }

    @objc private func showProgress() {
        if model.items.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Ready for progress"
            alert.informativeText = "Send an item to http://127.0.0.1:8766/items. Progress cards appear automatically."
            alert.runModal()
        } else { panel?.orderFrontRegardless() }
    }

    private func refreshPanel(reposition: Bool = false) {
        guard let panel else { return }
        statusItem?.button?.title = model.items.isEmpty ? "" : " \(model.items.count)"
        guard !model.items.isEmpty else { panel.orderOut(nil); return }
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let maximumHeight = max(160, screen.visibleFrame.height - 48)
        let wasVisible = panel.isVisible
        let hosting = panel.contentView as? NSHostingView<ProgressCard>
        let root = ProgressCard(model: model, maximumHeight: maximumHeight)
        if let hosting { hosting.rootView = root }
        else { panel.contentView = NSHostingView(rootView: root) }
        let height = min(CGFloat(model.items.count) * 116 + 82, maximumHeight)
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size = NSSize(width: 370, height: height)
        if !wasVisible || reposition {
            frame.origin = NSPoint(x: screen.visibleFrame.maxX - frame.width - 6,
                                   y: screen.visibleFrame.maxY - frame.height - 6)
        }
        frame.origin.y = max(screen.visibleFrame.minY, frame.origin.y)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !model.items.isEmpty { panel?.orderFrontRegardless() }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { server.stop() }
}

@main
struct ProgressNotifier {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
