import Foundation

public struct ProgressUpdate: Codable {
    public let name: String
    public let progress: Double
    public let etaSeconds: Double

    public init(name: String, progress: Double, etaSeconds: Double) {
        self.name = name
        self.progress = progress
        self.etaSeconds = etaSeconds
    }

    public func validated() throws -> ProgressUpdate {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 160,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw APIError(400, "name must contain 1–160 characters without control characters")
        }
        guard progress.isFinite, (0...100).contains(progress) else {
            throw APIError(400, "progress must be a number from 0 to 100")
        }
        guard etaSeconds.isFinite, (0...31_536_000).contains(etaSeconds) else {
            throw APIError(400, "etaSeconds must be seconds remaining, from 0 to 31536000")
        }
        return ProgressUpdate(name: name, progress: progress, etaSeconds: etaSeconds)
    }
}

public struct ProgressItem: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public var progress: Double
    public var expectedFinish: Date
    public var completing: Bool
}

public struct APIError: Error {
    public let status: Int
    public let message: String
    public init(_ status: Int, _ message: String) { self.status = status; self.message = message }
}

public struct ProgressSnapshot: Codable {
    public let items: [ProgressItem]
    public let dismissed: [String]
}

/// Accessed on the main queue. Dismissed names stay silent until their client sends 100%.
public final class ProgressRegistry {
    public private(set) var items: [ProgressItem] = []
    private var dismissed = Set<String>()
    public init(snapshot: ProgressSnapshot? = nil) {
        guard let snapshot else { return }
        var names = Set<String>()
        for item in snapshot.items where !item.completing && item.progress < 100 {
            guard items.count < 50, item.expectedFinish.timeIntervalSince1970.isFinite,
                  let value = try? ProgressUpdate(name: item.name, progress: item.progress, etaSeconds: 0).validated(),
                  value.name == item.name, names.insert(item.name).inserted else { continue }
            items.append(item)
        }
        dismissed = Set(snapshot.dismissed.filter { !names.contains($0) })
    }

    public var snapshot: ProgressSnapshot {
        ProgressSnapshot(items: items.filter { !$0.completing }, dismissed: dismissed.sorted())
    }

    /// Returns true exactly once when an item enters its completion animation.
    @discardableResult
    public func update(_ input: ProgressUpdate, now: Date = Date()) throws -> Bool {
        let value = try input.validated()
        if dismissed.contains(value.name) {
            if value.progress == 100 { dismissed.remove(value.name) }
            return false
        }
        if let index = items.firstIndex(where: { $0.name == value.name }) {
            guard !items[index].completing else { return false }
            items[index].progress = value.progress
            items[index].expectedFinish = now.addingTimeInterval(value.etaSeconds)
            items[index].completing = value.progress == 100
            return items[index].completing
        }
        // Unknown completions are no-ops, so retries cannot create phantom notifications.
        guard value.progress < 100 else { return false }
        guard items.count < 50 else { throw APIError(409, "At most 50 active items are supported") }
        items.append(ProgressItem(id: UUID(), name: value.name, progress: value.progress,
                                  expectedFinish: now.addingTimeInterval(value.etaSeconds), completing: false))
        return false
    }

    public func dismiss(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let item = items.first(where: { $0.name == name }), !item.completing {
            dismissed.insert(name)
        }
        items.removeAll { $0.name == name }
    }

    public func removeCompleted(id: UUID) {
        items.removeAll { $0.id == id && $0.completing }
    }
}
