import AppKit
import XCTest
import ProgressCore
@testable import ProgressNotifier

final class ModeActionTests: XCTestCase {
    func testHistoryDetailsAndUndoActionsPreserveMode() throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let originalMode = defaults.object(forKey: "compactMode")
        let originalTitles = defaults.object(forKey: "compactTitles")
        defer {
            if let originalTitles { defaults.set(originalTitles, forKey: "compactTitles") }
            else { defaults.removeObject(forKey: "compactTitles") }
            if let originalMode { defaults.set(originalMode, forKey: "compactMode") }
            else { defaults.removeObject(forKey: "compactMode") }
        }
        for (compact, titles) in [(false, false), (true, false), (true, true)] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let registry = ProgressRegistry()
            for name in ["Completed", "Closed", "Deleted"] {
                try registry.update(.init(name: name, progress: 25, etaSeconds: 60, description: "Started"))
            }
            try registry.update(.init(name: "Completed", progress: 100, etaSeconds: 0))
            registry.close(id: registry.items.first { $0.name == "Closed" }!.id)
            registry.dismiss(id: registry.items.first { $0.name == "Deleted" }!.id)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stateURL = directory.appendingPathComponent("state.json")
            try JSONEncoder().encode(registry.snapshot).write(to: stateURL)
            let model = ProgressModel(stateURL: stateURL)
            defaults.set(compact, forKey: "compactMode")
            defaults.set(titles, forKey: "compactTitles")
            let delegate = AppDelegate(model: model)
            for action in ["recallCompleted", "toggleUpdates", "toggleAllUpdates", "undoClose", "undoDeletion"] {
                _ = delegate.perform(NSSelectorFromString(action))
                XCTAssertEqual(defaults.bool(forKey: "compactMode"), compact, "\(action) changed mode")
                XCTAssertEqual(defaults.bool(forKey: "compactTitles"), titles, "\(action) changed title style")
            }
            XCTAssertEqual(Set(model.displayItems.map(\.name)), ["Completed", "Closed", "Deleted"])
        }
    }
    func testTitleShortcutTogglesMinimizedStylesAndPlainShortcutKeepsItsBehavior() {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let keys = ["compactMode", "compactTitles"]
        let originals = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, originals) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        // Starting mode, shortcut, expected mode. Shift+M must never expand the panel.
        let transitions: [(Bool, Bool, Bool, Bool, Bool)] = [
            (false, false, false, true, false),
            (false, true, false, true, false),
            (true, false, false, false, false),
            (true, true, false, true, false),
            (false, false, true, true, true),
            (false, true, true, true, true),
            (true, false, true, true, true),
            (true, true, true, true, false),
        ]
        for (compact, titles, requestedTitles, expectedCompact, expectedTitles) in transitions {
            defaults.set(compact, forKey: "compactMode")
            defaults.set(titles, forKey: "compactTitles")
            let delegate = AppDelegate()
            delegate.toggleCompact(showTitles: requestedTitles)
            XCTAssertEqual(defaults.bool(forKey: "compactMode"), expectedCompact)
            XCTAssertEqual(defaults.bool(forKey: "compactTitles"), expectedTitles)
        }
    }

}
