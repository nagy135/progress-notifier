import AppKit
import SwiftUI
import ProgressCore

final class ProgressModel: ObservableObject {
    @Published private(set) var items: [ProgressItem] = []
    private let registry: ProgressRegistry
    private let stateURL: URL
    var changed: (() -> Void)?
    private var sound: NSSound?
    private var revisions: [UUID: UInt64] = [:]

    func revision(for item: ProgressItem) -> UInt64 { revisions[item.id] ?? 0 }

    init() {
        stateURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Progress Notifier/state.json")
        let snapshot = (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode(ProgressSnapshot.self, from: $0) }
        registry = ProgressRegistry(snapshot: snapshot)
        items = registry.items
    }

    func dismiss(_ name: String) { registry.dismiss(name: name); publish() }

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
            return HTTPResponse(["app": "progress-notifier", "version": "1.2.0", "status": "ok"])
        }
        guard url.path == "/items" else { return HTTPResponse(404, ["error": "Unknown endpoint"]) }
        switch request.method {
        case "GET":
            let data: [[String: Any]] = items.map {
                var value: [String: Any] = ["name": $0.name, "progress": $0.progress,
                    "etaSeconds": max(0, $0.expectedFinish.timeIntervalSinceNow), "completing": $0.completing]
                if let project = $0.project { value["project"] = project }
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
                do { update = try JSONDecoder().decode(ProgressUpdate.self, from: request.body) }
                catch { throw APIError(400, "Expected JSON: name (string), progress (0–100), etaSeconds (seconds remaining); optional project must be a string and projectIcon must be a T3 project icon object") }
                let name = update.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let wasCompleting = registry.items.first(where: { $0.name == name })?.completing ?? false
                let completed = try registry.update(update)
                if !wasCompleting, let item = registry.items.first(where: { $0.name == name }) {
                    revisions[item.id, default: 0] &+= 1
                }
                publish()
                if completed, let item = items.first(where: { $0.name == update.name.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                    sound = NSSound(named: "Glass")
                    if sound?.play() != true { NSSound.beep() }
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { items = registry.items }
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
