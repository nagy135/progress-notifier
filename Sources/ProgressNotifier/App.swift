import AppKit
import SwiftUI

private final class ProgressPanel: NSPanel {
    var hideProgress: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func close() { hideProgress?() }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = ProgressModel()
    private let server = HTTPServer()
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private var statusLine: NSMenuItem?
    private var screenObserver: NSObjectProtocol?
    private var keyboardMonitor: Any?
    private var windowHidden = false
    private var compact = UserDefaults.standard.bool(forKey: "compactMode")
    private var expandedContentHeight: CGFloat?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenu = NSMenu()
        let hide = NSMenuItem(title: "Close Progress Window", action: #selector(hideProgress), keyEquivalent: "w")
        hide.target = self
        appMenu.addItem(hide)
        appMenu.addItem(withTitle: "Quit Progress Notifier", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Progress Notifier")
        let menu = NSMenu()
        let line = NSMenuItem(title: "Starting local API…", action: nil, keyEquivalent: "")
        menu.addItem(line)
        menu.addItem(.separator())
        let show = NSMenuItem(title: "Show Progress", action: #selector(showProgress), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let hideItem = NSMenuItem(title: "Close Progress Window", action: #selector(hideProgress), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)
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
        panel.hideProgress = { [weak self] in self?.hideProgress() }
        self.panel = panel
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "q": self.hideProgress(); return nil
            case "m": self.toggleCompact(); return nil
            default: return event
            }
        }
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
        refreshPanel()
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
        windowHidden = false
        refreshPanel()
        panel?.makeKeyAndOrderFront(nil)
    }

    @objc private func hideProgress() {
        windowHidden = true
        panel?.orderOut(nil)
    }

    private func toggleCompact() {
        compact.toggle()
        UserDefaults.standard.set(compact, forKey: "compactMode")
        refreshPanel()
    }

    private func refreshPanel(reposition: Bool = false) {
        guard let panel else { return }
        statusItem?.button?.title = model.items.isEmpty ? "" : " \(model.items.count)"
        guard !windowHidden else { return }
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let maximumHeight = max(160, screen.visibleFrame.height - 48)
        let wasVisible = panel.isVisible
        let hosting = panel.contentView as? NSHostingView<ProgressCard>
        let root = ProgressCard(model: model, maximumHeight: maximumHeight, compact: compact,
                                expandedContentHeight: expandedContentHeight,
                                contentHeightChanged: { [weak self] height in
                                    guard let self, abs((self.expandedContentHeight ?? 0) - height) > 0.5 else { return }
                                    self.expandedContentHeight = height
                                    self.refreshPanel()
                                },
                                toggleCompact: { [weak self] in self?.toggleCompact() },
                                close: { [weak self] in self?.hideProgress() })
        if let hosting { hosting.rootView = root }
        else {
            let hosting = NSHostingView(rootView: root)
            hosting.sizingOptions = []
            panel.contentView = hosting
        }
        let height = compact ? ProgressCard.compactHeight(itemCount: model.items.count, maximumHeight: maximumHeight)
            : model.items.isEmpty ? 100 + ProgressCard.expandedChromeHeight
            : min((expandedContentHeight ?? CGFloat(model.items.count) * 100 + 8) + ProgressCard.expandedChromeHeight, maximumHeight)
        var frame = panel.frame
        let rightEdge = frame.maxX
        frame.origin.y += frame.height - height
        frame.size = NSSize(width: compact ? 216 : 370, height: height)
        frame.origin.x = rightEdge - frame.width
        if !wasVisible || reposition {
            frame.origin = NSPoint(x: screen.visibleFrame.maxX - frame.width - 6,
                                   y: screen.visibleFrame.maxY - frame.height - 6)
        }
        frame.origin.y = max(screen.visibleFrame.minY, frame.origin.y)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showProgress()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        server.stop()
    }
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
