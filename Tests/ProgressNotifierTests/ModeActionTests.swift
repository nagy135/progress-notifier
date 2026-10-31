import AppKit
import XCTest
import ProgressCore
@testable import ProgressNotifier

final class ModeActionTests: XCTestCase {
    func testHistoryDetailsAndUndoActionsPreserveMode() throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let originalMode = defaults.object(forKey: "compactMode")
        defer {
            if let originalMode { defaults.set(originalMode, forKey: "compactMode") }
            else { defaults.removeObject(forKey: "compactMode") }
        }
        for compact in [false, true] {
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
            let delegate = AppDelegate(model: model)
            for action in ["recallCompleted", "toggleUpdates", "toggleAllUpdates", "undoClose", "undoDeletion"] {
                _ = delegate.perform(NSSelectorFromString(action))
                XCTAssertEqual(defaults.bool(forKey: "compactMode"), compact, "\(action) changed mode")
            }
            XCTAssertEqual(Set(model.displayItems.map(\.name)), ["Completed", "Closed", "Deleted"])
        }
    }
}
