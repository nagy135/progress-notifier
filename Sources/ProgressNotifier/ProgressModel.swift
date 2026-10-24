import AppKit
import SwiftUI
import ProgressCore

final class ProgressModel: ObservableObject {
    @Published private(set) var items: [ProgressItem] = []
    private let registry = ProgressRegistry()
    var changed: (() -> Void)?
    private var sound: NSSound?

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
            return HTTPResponse(["app": "progress-notifier", "version": "1.0.0", "status": "ok"])
        }
        guard url.path == "/items" else { return HTTPResponse(404, ["error": "Unknown endpoint"]) }
        switch request.method {
        case "GET":
            let data: [[String: Any]] = items.map {
                ["name": $0.name, "progress": $0.progress,
                 "etaSeconds": max(0, $0.expectedFinish.timeIntervalSinceNow), "completing": $0.completing]
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
                catch { throw APIError(400, "Expected JSON: name (string), progress (0–100), etaSeconds (seconds remaining)") }
                let completed = try registry.update(update)
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { items = registry.items }
        changed?()
    }
}

private extension HTTPResponse {
    init(_ value: Any) { self.init(200, value) }
}
