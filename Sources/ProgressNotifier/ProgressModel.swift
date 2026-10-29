import AppKit
import SwiftUI
import ProgressCore

final class ProgressModel: ObservableObject {
    @Published private(set) var items: [ProgressItem] = []
    @Published private(set) var recalledItems: [ProgressItem] = []
    @Published var isFocused = false
    var displayItems: [ProgressItem] { registry.visibleItems.filter { !$0.completing } + recalledItems }
    var hasHistory: Bool { !registry.history.isEmpty }
    private let registry: ProgressRegistry
    private let stateURL: URL
    var changed: (() -> Void)?
    private var sound: NSSound?
    private let completionFeedback: (() -> Void)?
    private var revisions: [UUID: UInt64] = [:]
    private var flashedRevisions: [UUID: UInt64] = [:]

    func revision(for item: ProgressItem) -> UInt64 { revisions[item.id] ?? 0 }

    // Keep this outside the views so changing layouts cannot replay an update.
    func consumeUpdatePulse(for item: ProgressItem) -> Bool {
        let revision = revision(for: item)
        guard revision > 0, flashedRevisions[item.id] != revision else { return false }
        flashedRevisions[item.id] = revision
        return true
    }

    init(stateURL: URL? = nil, completionFeedback: (() -> Void)? = nil) {
        self.completionFeedback = completionFeedback
        self.stateURL = stateURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Progress Notifier/state.json")
        let snapshot = (try? Data(contentsOf: self.stateURL)).flatMap { try? JSONDecoder().decode(ProgressSnapshot.self, from: $0) }
        registry = ProgressRegistry(snapshot: snapshot)
        items = registry.items
    }

    func dismiss(_ name: String) { registry.dismiss(name: name); publish() }
    func dismiss(_ item: ProgressItem) { registry.dismiss(id: item.id); publish() }
    func close(_ item: ProgressItem) { registry.close(id: item.id); publish() }

    @discardableResult
    func undoClose() -> ProgressItem? {
        guard let item = registry.undoClose() else { return nil }
        publish()
        return item
    }

    @discardableResult
    func undoDeletion() -> ProgressItem? {
        guard let item = registry.deletions.last?.item, registry.undoDeletion() else { return nil }
        publish()
        return item
    }

    @discardableResult
    func recallCompleted() -> Bool {
        guard registry.revealNextCompleted() else { return false }
        publish()
        return true
    }

    func clearCompleted() { registry.clearCompleted(); publish() }

    func handle(_ request: HTTPRequest) -> HTTPResponse {
        guard request.headers["origin"] == nil,
              request.headers["sec-fetch-site"] != "cross-site" else {
            return HTTPResponse(403, ["error": "Browser-origin requests are not supported; use a local client"])
        }
        guard var url = URLComponents(string: request.target) else {
            return HTTPResponse(400, ["error": "Invalid URL"])
        }
        // Standard clients encode query spaces as +; an actual plus arrives as %2B.
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
        if url.path == "/health", request.method == "GET" {
            return HTTPResponse(["app": "progress-notifier", "version": "1.5.0", "status": "ok"])
        }
        guard url.path == "/items" else { return HTTPResponse(404, ["error": "Unknown endpoint"]) }
        switch request.method {
        case "GET":
            let timestamp = ISO8601DateFormatter()
            timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let data: [[String: Any]] = items.map {
                var value: [String: Any] = ["name": $0.name, "progress": $0.progress,
                    "etaSeconds": max(0, $0.expectedFinish.timeIntervalSinceNow), "completing": $0.completing]
                value["updates"] = $0.updates.map { entry -> [String: Any] in
                    ["id": entry.id.uuidString, "description": entry.description,
                     "progress": entry.progress, "recordedAt": timestamp.string(from: entry.recordedAt)]
                }
                value["updateCount"] = $0.updates.count
                value["isChild"] = $0.isChild
                if let latest = $0.updates.first { value["description"] = latest.description }
                if let project = $0.project { value["project"] = project }
                if let thread = $0.t3Thread {
                    value["t3Thread"] = ["environmentId": thread.environmentId, "threadId": thread.threadId]
                }
                if let icon = $0.projectIcon,
                   let data = try? JSONEncoder().encode(icon),
                   let object = try? JSONSerialization.jsonObject(with: data) { value["projectIcon"] = object }
                return value
            }
            return HTTPResponse(["items": data])
        case "DELETE":
            guard let name = url.queryItems?.first(where: { $0.name == "name" })?.value, !name.isEmpty else {
                return HTTPResponse(400, ["error": "Supply ?name= with the item name"])
            }
            dismiss(name)
            return HTTPResponse(["ok": true])
        case "POST":
            guard request.headers["content-type"]?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json" else {
                return HTTPResponse(415, ["error": "Use Content-Type: application/json"])
            }
            do {
                let update: ProgressUpdate
                do { update = try JSONDecoder().decode(ProgressUpdate.self, from: request.body).validated() }
                catch let error as APIError { throw error }
                catch { throw APIError(400, "Expected JSON: name (string), progress (0–100), etaSeconds (seconds remaining); optional description and project must be strings, projectIcon must be a T3 project icon object, isChild must be a boolean, and t3Thread must contain environmentId and threadId strings") }
                // Deleted updates acknowledge receipt without saving, publishing, or feedback.
                guard !registry.isDeleted(update) else { return HTTPResponse(["ok": true]) }
                let wasCompleting = registry.item(for: update)?.completing ?? false
                let completed = try registry.update(update)
                if !wasCompleting, let item = registry.item(for: update) {
                    revisions[item.id, default: 0] &+= 1
                }
                publish()
                if completed, let item = registry.item(for: update) {
                    if let completionFeedback { completionFeedback() }
                    else {
                        sound = NSSound(named: "Glass")
                        if sound?.play() != true { NSSound.beep() }
                    }
                    // Retire the API entry after feedback, while keeping the same visible history ID.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { [weak self] in
                        self?.registry.removeCompleted(id: item.id)
                        self?.publish()
                    }
                }
                return HTTPResponse(["ok": true])
            } catch let error as APIError { return HTTPResponse(error.status, ["error": error.message]) }
            catch { return HTTPResponse(500, ["error": "Could not update item"]) }
        default: return HTTPResponse(405, ["error": "Use GET, POST, or DELETE"])
        }
    }

    private func publish() {
        let ids = Set(registry.items.map(\.id))
        revisions = revisions.filter { ids.contains($0.key) }
        flashedRevisions = flashedRevisions.filter { ids.contains($0.key) }
        // Presentation owns geometry animation; publishing must not start a competing spring.
        items = registry.items
        recalledItems = registry.revealedHistory
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(registry.snapshot).write(to: stateURL, options: .atomic)
        } catch { NSLog("Could not save progress: %@", error.localizedDescription) }
        changed?()
    }
}

private extension HTTPResponse {
    init(_ value: Any) { self.init(200, value) }
}
