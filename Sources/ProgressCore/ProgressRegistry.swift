import Foundation

public struct ProgressUpdate: Codable {
    public let name: String
    public let progress: Double
    public let etaSeconds: Double
    public let project: String?
    public let projectIcon: ProjectIcon?

    public init(name: String, progress: Double, etaSeconds: Double, project: String? = nil, projectIcon: ProjectIcon? = nil) {
        self.name = name
        self.progress = progress
        self.etaSeconds = etaSeconds
        self.project = project
        self.projectIcon = projectIcon
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
        return ProgressUpdate(name: name, progress: progress, etaSeconds: etaSeconds,
                              project: try Self.metadata(project, field: "project", limit: 160),
                              projectIcon: try projectIcon?.validated())
    }

    private static func metadata(_ input: String?, field: String, limit: Int) throws -> String? {
        guard let input else { return nil }
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= limit,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw APIError(400, "\(field) must contain at most \(limit) characters without control characters")
        }
        return value
    }
}

public struct ProgressItem: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public var progress: Double
    public var expectedFinish: Date
    public var completing: Bool
    public var project: String?
    public var projectIcon: ProjectIcon?
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
                  let value = try? ProgressUpdate(name: item.name, progress: item.progress, etaSeconds: 0,
                                                 project: item.project, projectIcon: item.projectIcon).validated(),
                  value.name == item.name, names.insert(item.name).inserted else { continue }
            var restored = item
            restored.project = value.project.flatMap { $0.isEmpty ? nil : $0 }
            restored.projectIcon = value.projectIcon
            items.append(restored)
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
            if let project = value.project { items[index].project = project.isEmpty ? nil : project }
            if let projectIcon = value.projectIcon { items[index].projectIcon = projectIcon }
            if value.project?.isEmpty == true { items[index].projectIcon = nil }
            return items[index].completing
        }
        // Unknown completions are no-ops, so retries cannot create phantom notifications.
        guard value.progress < 100 else { return false }
        guard items.count < 50 else { throw APIError(409, "At most 50 active items are supported") }
        items.append(ProgressItem(id: UUID(), name: value.name, progress: value.progress,
                                  expectedFinish: now.addingTimeInterval(value.etaSeconds), completing: false,
                                  project: value.project.flatMap { $0.isEmpty ? nil : $0 },
                                  projectIcon: value.projectIcon))
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
