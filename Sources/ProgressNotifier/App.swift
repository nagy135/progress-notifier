import AppKit
import SwiftUI

private final class ProgressPanel: NSPanel {
    var hideProgress: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func close() { hideProgress?() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = ProgressModel()
    private let server = HTTPServer()
    private var panel: ProgressPanel?
    private var statusItem: NSStatusItem?
    private var statusLine: NSMenuItem?
    private var screenObserver: NSObjectProtocol?
    private var keyboardMonitor: Any?
    private var windowHidden = false
    private var compact = UserDefaults.standard.bool(forKey: "compactMode")
    private var placement = PanelPlacement(rawValue: UserDefaults.standard.string(forKey: "panelPlacement") ?? "") ?? .topRight
    private let presentation = ProgressPresentation(compact: UserDefaults.standard.bool(forKey: "compactMode"))

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenu = NSMenu()
        let hide = NSMenuItem(title: "Close Progress Window", action: #selector(hideProgress), keyEquivalent: "w")
        hide.target = self
        appMenu.addItem(hide)
        addProgressActions(to: appMenu)
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
        addProgressActions(to: menu)
        menu.addItem(withTitle: "Quit Progress Notifier", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        statusLine = line

        let panel = ProgressPanel(contentRect: NSRect(x: 0, y: 0, width: 370, height: 200),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Progress Notifier"
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hideProgress = { [weak self] in self?.hideProgress() }
        self.panel = panel
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            // Use the same current key status for shortcuts and the focus outline.
            self.model.isFocused = panel.isKeyWindow
            guard panel.isKeyWindow,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 125: self.presentation.moveFocus(by: 1, animated: true); return nil
            case 126: self.presentation.moveFocus(by: -1, animated: true); return nil
            default: break
            }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "j": self.presentation.moveFocus(by: 1, animated: true); return nil
            case "k": self.presentation.moveFocus(by: -1, animated: true); return nil
            case "q": self.hideProgress(); return nil
            case "m": self.toggleCompact(); return nil
            case ".":
                if !event.isARepeat { self.togglePlacement() }
                return nil
            case "h": self.recallCompleted(); return nil
            case "c": self.model.clearCompleted(); return nil
            case "x":
                if !event.isARepeat {
                    if event.modifierFlags.contains(.shift) { self.undoClose() }
                    else { self.closeFocusedTask() }
                }
                return nil
            case "z":
                if !event.isARepeat {
                    if event.modifierFlags.contains(.shift) { self.undoDeletion() }
                    else { self.deleteFocusedTask() }
                }
                return nil
            case "d":
                if !event.isARepeat {
                    if event.modifierFlags.contains(.shift) { self.toggleAllUpdates() }
                    else { self.toggleUpdates() }
                }
                return nil
            default: return event
            }
        }
        presentation.geometryChanged = { [weak self] in self?.resizePanel() }
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
        // Keep mode and history shortcuts available after a background click.
        panel?.makeKeyAndOrderFront(nil)
        setCompact(!compact)
    }

    private func setCompact(_ compact: Bool) {
        self.compact = compact
        UserDefaults.standard.set(compact, forKey: "compactMode")
        refreshPanel()
    }

    @objc private func togglePlacement() {
        placement = placement.toggled
        UserDefaults.standard.set(placement.rawValue, forKey: "panelPlacement")
        if let hosting = panel?.contentView as? NSHostingView<PanelContent<ProgressCard>> {
            hosting.rootView.placement = placement
        }
        resizePanel(reposition: true)
    }

    private func addProgressActions(to menu: NSMenu) {
        menu.addItem(.separator())
        let corner = NSMenuItem(title: "Switch Top / Bottom Corner (.)", action: #selector(togglePlacement), keyEquivalent: "")
        corner.target = self
        menu.addItem(corner)
        let updates = NSMenuItem(title: "Toggle Focused Task Details (D)", action: #selector(toggleUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)
        let allUpdates = NSMenuItem(title: "Toggle All Task Details (Shift+D)", action: #selector(toggleAllUpdates), keyEquivalent: "")
        allUpdates.target = self
        menu.addItem(allUpdates)
        let recall = NSMenuItem(title: "Recall Completed Result (H)", action: #selector(recallCompleted), keyEquivalent: "")
        recall.target = self
        menu.addItem(recall)
        let clear = NSMenuItem(title: "Clear Completed Results (C)", action: #selector(clearCompleted), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        let close = NSMenuItem(title: "Close Focused Task (X)", action: #selector(closeFocusedTask), keyEquivalent: "")
        close.target = self
        menu.addItem(close)
        let undoClose = NSMenuItem(title: "Undo Task Close (Shift+X)", action: #selector(undoClose), keyEquivalent: "")
        undoClose.target = self
        menu.addItem(undoClose)
        let delete = NSMenuItem(title: "Delete Focused Task (Z)", action: #selector(deleteFocusedTask), keyEquivalent: "")
        delete.target = self
        menu.addItem(delete)
        let undo = NSMenuItem(title: "Undo Task Deletion (Shift+Z)", action: #selector(undoDeletion), keyEquivalent: "")
        undo.target = self
        menu.addItem(undo)
        menu.addItem(.separator())
    }

    @objc private func toggleUpdates() {
        let wasCompact = compact
        if compact { setCompact(false) }
        guard presentation.focusedItemID != nil else { return }
        // D from compact opens the remembered ledger; further presses fold its history.
        presentation.setShowsUpdates(wasCompact || !presentation.showsUpdates, animated: panel?.isVisible == true)
        refreshPanel()
    }

    @objc private func toggleAllUpdates() {
        if compact { setCompact(false) }
        guard presentation.focusedItemID != nil else { return }
        presentation.toggleAllUpdates(animated: panel?.isVisible == true)
        refreshPanel()
    }

    @objc private func recallCompleted() {
        guard model.recallCompleted() else { return }
        setCompact(false)
        showProgress()
    }

    @objc private func clearCompleted() { model.clearCompleted() }

    @objc private func closeFocusedTask() {
        guard let item = presentation.focusedItem else { return }
        model.close(item)
    }

    @objc private func undoClose() {
        guard let item = model.undoClose() else { return }
        setCompact(false)
        showProgress()
        presentation.focus(item.id, animated: true)
    }

    @objc private func deleteFocusedTask() {
        guard let item = presentation.focusedItem else { return }
        model.dismiss(item)
    }

    @objc private func undoDeletion() {
        guard let item = model.undoDeletion() else { return }
        setCompact(false)
        showProgress()
        presentation.focus(item.id, animated: true)
    }

    private func refreshPanel(reposition: Bool = false) {
        guard let panel else { return }
        statusItem?.button?.title = model.items.isEmpty ? "" : " \(model.items.count)"
        guard !windowHidden else { return }
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        presentation.maximumHeight = max(160, screen.visibleFrame.height - 48)
        if panel.contentView as? NSHostingView<PanelContent<ProgressCard>> == nil {
            let root = ProgressCard(model: model, presentation: presentation,
                                    detailsHeightsChanged: { [weak self] heights in
                                        guard let self else { return }
                                        self.presentation.measure(heights, animated: self.panel?.isVisible == true)
                                    },
                                    historyHeightsChanged: { [weak self] heights in
                                        guard let self else { return }
                                        self.presentation.measureHistory(heights, animated: self.panel?.isVisible == true)
                                    },
                                    toggleUpdates: { [weak self] in self?.toggleUpdates() },
                                    toggleCompact: { [weak self] in self?.toggleCompact() },
                                    close: { [weak self] in self?.hideProgress() })
            let hosting = NSHostingView(rootView: PanelContent(placement: placement) { root })
            hosting.sizingOptions = []
            panel.contentView = hosting
        }
        presentation.update(items: model.displayItems, compact: compact, animated: panel.isVisible)
        resizePanel(reposition: reposition)
        panel.orderFrontRegardless()
    }

    private func resizePanel(reposition: Bool = false) {
        guard let panel, !windowHidden,
              let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = placement.frame(resizing: panel.frame,
                                    to: NSSize(width: presentation.windowWidth, height: presentation.windowHeight),
                                    in: screen.visibleFrame, reposition: !panel.isVisible || reposition)
        panel.setFrame(frame, display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showProgress()
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.isFocused = true
    }

    func windowDidResignKey(_ notification: Notification) {
        model.isFocused = false
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
