import Foundation

public struct ProgressUpdate: Codable {
    public let name: String
    public let progress: Double
    public let etaSeconds: Double
    public let project: String?
    public let projectIcon: ProjectIcon?
    public let description: String?
    public let t3Thread: T3ThreadReference?

    public init(name: String, progress: Double, etaSeconds: Double, project: String? = nil, projectIcon: ProjectIcon? = nil, description: String? = nil, t3Thread: T3ThreadReference? = nil) {
        self.name = name
        self.progress = progress
        self.etaSeconds = etaSeconds
        self.project = project
        self.projectIcon = projectIcon
        self.description = description
        self.t3Thread = t3Thread
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
                              projectIcon: try projectIcon?.validated(),
                              description: try Self.normalizedDescription(description),
                              t3Thread: try t3Thread?.validated())
    }

    public static let descriptionLimit = 2_000

    public static func normalizedDescription(_ input: String?) throws -> String? {
        guard let input else { return nil }
        let value = input.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= descriptionLimit,
              !value.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
              }) else {
            throw APIError(400, "description must contain at most 2000 characters; only newline and tab control characters are supported")
        }
        return value.isEmpty ? nil : value
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

public struct ProgressEntry: Codable, Identifiable {
    public let id: UUID
    public let description: String
    public let progress: Double
    public let recordedAt: Date
}

public struct ProgressItem: Codable, Identifiable {
    public let id: UUID
    public let name: String
    // Older snapshots did not record this date.
    public let createdAt: Date?
    public var completedAt: Date?
    public var progress: Double
    public var expectedFinish: Date
    public var completing: Bool
    public var project: String?
    public var projectIcon: ProjectIcon?
    public var t3Thread: T3ThreadReference? = nil
    public var updates: [ProgressEntry] = []

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, completedAt, progress, expectedFinish, completing, project, projectIcon, t3Thread, updates
    }

}

extension ProgressItem {
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        progress = try values.decode(Double.self, forKey: .progress)
        expectedFinish = try values.decode(Date.self, forKey: .expectedFinish)
        completing = try values.decode(Bool.self, forKey: .completing)
        project = try values.decodeIfPresent(String.self, forKey: .project)
        projectIcon = try values.decodeIfPresent(ProjectIcon.self, forKey: .projectIcon)
        t3Thread = try values.decodeIfPresent(T3ThreadReference.self, forKey: .t3Thread)
        updates = try values.decodeIfPresent([ProgressEntry].self, forKey: .updates) ?? []
    }
}

public struct APIError: Error {
    public let status: Int
    public let message: String
    public init(_ status: Int, _ message: String) { self.status = status; self.message = message }
}

public struct ProgressSnapshot: Codable {
    public let items: [ProgressItem]
    public let dismissed: [String]
    public let history: [ProgressItem]?
    public var deletions: [ProgressDeletion]? = nil
    public var closedItemIDs: [UUID]? = nil
    public var closures: [ProgressClosure]? = nil
}

public struct ProgressDeletion: Codable {
    public let item: ProgressItem
    public let index: Int
}

public struct ProgressClosure: Codable {
    public let item: ProgressItem
    public let index: Int
}

/// Accessed on the main queue. Deleted names stay silent until undo.
public final class ProgressRegistry {
    public static let updateLimit = 200
    public static let historyLimit = 200
    public private(set) var items: [ProgressItem] = []
    public private(set) var history: [ProgressItem] = []
    private var revealedHistoryIDs = Set<UUID>()
    private var visitedHistoryIDs = Set<UUID>()
    private var dismissed = Set<String>()
    private var closedItemIDs = Set<UUID>()
    public private(set) var deletions: [ProgressDeletion] = []
    public private(set) var closures: [ProgressClosure] = []
    public init(snapshot: ProgressSnapshot? = nil) {
        guard let snapshot else { return }
        var names = Set<String>()
        for item in snapshot.items where !item.completing && item.progress < 100 {
            guard items.count < 50, let restored = Self.restored(item),
                  names.insert(item.name).inserted else { continue }
            items.append(restored)
        }
        var ids = Set(items.map(\.id))
        for item in snapshot.history ?? [] where item.completing && item.progress == 100 {
            guard history.count < Self.historyLimit, let restored = Self.restored(item),
                  ids.insert(item.id).inserted else { continue }
            history.append(restored)
        }
        dismissed = Set(snapshot.dismissed.filter { !names.contains($0) })
        closedItemIDs = Set(snapshot.closedItemIDs ?? []).intersection(items.map(\.id))
        var deletedIDs = Set<UUID>()
        var deletedNames = names
        for deletion in snapshot.deletions ?? [] {
            guard let item = Self.restored(deletion.item), deletion.index >= 0,
                  !ids.contains(item.id), deletedIDs.insert(item.id).inserted else { continue }
            if !item.completing {
                guard deletedNames.insert(item.name).inserted else { continue }
            }
            deletions.append(ProgressDeletion(item: item, index: deletion.index))
        }
        let bannedIDs = Set(deletions.map(\.item.id))
        var closureIDs = Set<UUID>()
        for closure in snapshot.closures ?? [] {
            guard let item = Self.restored(closure.item), closure.index >= 0,
                  !bannedIDs.contains(item.id),
                  item.completing ? item.progress == 100 : items.contains(where: { $0.id == item.id }),
                  closureIDs.insert(item.id).inserted else { continue }
            closures.append(ProgressClosure(item: item, index: closure.index))
            if !item.completing { closedItemIDs.insert(item.id) }
        }
        // Older snapshots saved hidden active IDs without their close order.
        for (index, item) in items.enumerated() where closedItemIDs.contains(item.id) && !closureIDs.contains(item.id) {
            closures.append(ProgressClosure(item: item, index: index))
        }
    }

    private static func restored(_ item: ProgressItem) -> ProgressItem? {
        guard item.expectedFinish.timeIntervalSince1970.isFinite,
              item.createdAt?.timeIntervalSince1970.isFinite != false,
              item.completedAt?.timeIntervalSince1970.isFinite != false,
              let value = try? ProgressUpdate(name: item.name, progress: item.progress, etaSeconds: 0,
                                             project: item.project, projectIcon: item.projectIcon).validated(),
              value.name == item.name else { return nil }
        var restored = item
        restored.project = value.project.flatMap { $0.isEmpty ? nil : $0 }
        restored.projectIcon = value.projectIcon
        // A bad saved destination must not discard the task itself.
        restored.t3Thread = try? item.t3Thread?.validated()
        var ids = Set<UUID>()
        restored.updates = item.updates.compactMap { entry in
            guard entry.progress.isFinite, (0...100).contains(entry.progress),
                  entry.recordedAt.timeIntervalSince1970.isFinite,
                  let text = try? ProgressUpdate.normalizedDescription(entry.description),
                  ids.insert(entry.id).inserted else { return nil }
            return ProgressEntry(id: entry.id, description: text, progress: entry.progress, recordedAt: entry.recordedAt)
        }.prefix(updateLimit).map { $0 }
        return restored
    }

    public var snapshot: ProgressSnapshot {
        ProgressSnapshot(items: items.filter { !$0.completing }, dismissed: dismissed.sorted(), history: history,
                         deletions: deletions, closedItemIDs: closedItemIDs.sorted { $0.uuidString < $1.uuidString },
                         closures: closures)
    }

    public var visibleItems: [ProgressItem] {
        items.filter { !closedItemIDs.contains($0.id) }
    }

    public var revealedHistory: [ProgressItem] {
        history.filter { revealedHistoryIDs.contains($0.id) }
    }

    /// Recalls one hidden result per press, newest first, skipping automatically shown completions.
    @discardableResult
    public func revealNextCompleted() -> Bool {
        let liveIDs = Set(items.map(\.id))
        guard let item = history.first(where: { !visitedHistoryIDs.contains($0.id) && !liveIDs.contains($0.id) }) else {
            return false
        }
        visitedHistoryIDs.insert(item.id)
        revealedHistoryIDs.insert(item.id)
        closures.removeAll { $0.item.id == item.id }
        return true
    }

    /// Hiding results never deletes their history; the next recall starts at the newest again.
    public func clearCompleted() {
        items.removeAll { $0.completing }
        revealedHistoryIDs.removeAll()
        visitedHistoryIDs.removeAll()
    }

    /// Returns true exactly once when an item enters its completion animation.
    @discardableResult
    public func update(_ input: ProgressUpdate, now: Date = Date()) throws -> Bool {
        let value = try input.validated()
        guard !isDeleted(value) else { return false }
        if dismissed.contains(value.name) {
            if value.progress == 100 { dismissed.remove(value.name) }
            return false
        }
        if let index = items.firstIndex(where: { $0.name == value.name }) {
            guard !items[index].completing else { return false }
            closedItemIDs.remove(items[index].id)
            closures.removeAll { $0.item.id == items[index].id }
            items[index].progress = value.progress
            items[index].expectedFinish = now.addingTimeInterval(value.etaSeconds)
            items[index].completing = value.progress == 100
            if let project = value.project { items[index].project = project.isEmpty ? nil : project }
            if let projectIcon = value.projectIcon { items[index].projectIcon = projectIcon }
            if value.project?.isEmpty == true { items[index].projectIcon = nil }
            if let t3Thread = value.t3Thread { items[index].t3Thread = t3Thread }
            Self.record(value.description, progress: value.progress, on: &items[index], now: now)
            if items[index].completing {
                items[index].completedAt = now
                history.insert(items[index], at: 0)
                // A completion is visible history immediately, not an expiring card.
                revealedHistoryIDs.insert(items[index].id)
                visitedHistoryIDs.insert(items[index].id)
                history = Array(history.prefix(Self.historyLimit))
                let ids = Set(history.map(\.id))
                revealedHistoryIDs.formIntersection(ids)
                visitedHistoryIDs.formIntersection(ids)
            }
            return items[index].completing
        }
        // Unknown completions are no-ops, so retries cannot create phantom notifications.
        guard value.progress < 100 else { return false }
        guard items.count < 50 else { throw APIError(409, "At most 50 active items are supported") }
        items.append(ProgressItem(id: UUID(), name: value.name, createdAt: now, completedAt: nil, progress: value.progress,
                                  expectedFinish: now.addingTimeInterval(value.etaSeconds), completing: false,
                                  project: value.project.flatMap { $0.isEmpty ? nil : $0 },
                                  projectIcon: value.projectIcon, t3Thread: value.t3Thread))
        Self.record(value.description, progress: value.progress, on: &items[items.count - 1], now: now)
        return false
    }

    private static func record(_ description: String?, progress: Double, on item: inout ProgressItem, now: Date) {
        guard let description else { return }
        if let latest = item.updates.first, latest.description == description, latest.progress == progress { return }
        // Receipt order is authoritative, including equal timestamps and regressing percentages.
        item.updates.insert(ProgressEntry(id: UUID(), description: description, progress: progress, recordedAt: now), at: 0)
        item.updates = Array(item.updates.prefix(updateLimit))
    }

    public func dismiss(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let item = items.first(where: { $0.name == name }) {
            dismiss(id: item.id)
        } else {
            for item in revealedHistory where item.name == name { dismiss(id: item.id) }
        }
    }

    public func removeCompleted(id: UUID) {
        items.removeAll { $0.id == id && $0.completing }
    }

    /// Close only the current card. The next accepted update shows the same task again.
    public func close(id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id && !$0.completing }) {
            guard !closedItemIDs.contains(id) else { return }
            closures.append(ProgressClosure(item: items[index], index: index))
            closedItemIDs.insert(id)
        } else if let index = history.firstIndex(where: { $0.id == id }), revealedHistoryIDs.contains(id) {
            closures.append(ProgressClosure(item: history[index], index: index))
            items.removeAll { $0.id == id && $0.completing }
            revealedHistoryIDs.remove(id)
            visitedHistoryIDs.remove(id)
        }
    }

    /// Restores closed cards only. Updates and H recall consume their close entries.
    @discardableResult
    public func undoClose() -> ProgressItem? {
        while let closure = closures.popLast() {
            let item = closure.item
            if item.completing {
                if !history.contains(where: { $0.id == item.id }) {
                    history.insert(item, at: min(closure.index, history.count, Self.historyLimit - 1))
                    history = Array(history.prefix(Self.historyLimit))
                    let ids = Set(history.map(\.id))
                    revealedHistoryIDs.formIntersection(ids)
                    visitedHistoryIDs.formIntersection(ids)
                }
                revealedHistoryIDs.insert(item.id)
                visitedHistoryIDs.insert(item.id)
                return item
            }
            if let current = items.first(where: { $0.id == item.id }), closedItemIDs.remove(item.id) != nil {
                return current
            }
        }
        return nil
    }

    public func dismiss(id: UUID) {
        let item: ProgressItem
        let index: Int
        if let activeIndex = items.firstIndex(where: { $0.id == id && !$0.completing }) {
            item = items[activeIndex]
            index = activeIndex
        } else if let historyIndex = history.firstIndex(where: { $0.id == id }),
                  revealedHistoryIDs.contains(id) {
            item = history[historyIndex]
            index = historyIndex
        } else { return }
        deletions.append(ProgressDeletion(item: item, index: index))
        closures.removeAll { $0.item.id == id }
        closedItemIDs.remove(id)
        items.removeAll { $0.id == id }
        history.removeAll { $0.id == id }
        revealedHistoryIDs.remove(id)
        visitedHistoryIDs.remove(id)
    }

    public func isDeleted(_ update: ProgressUpdate) -> Bool {
        deletions.contains { $0.item.name == update.name }
    }

    public func item(for update: ProgressUpdate) -> ProgressItem? {
        items.first { $0.name == update.name }
    }

    /// A full active list leaves the stack intact so undo can be retried later.
    @discardableResult
    public func undoDeletion() -> Bool {
        guard let deletion = deletions.last else { return false }
        let item = deletion.item
        if item.completing {
            history.insert(item, at: min(deletion.index, history.count, Self.historyLimit - 1))
            history = Array(history.prefix(Self.historyLimit))
            let ids = Set(history.map(\.id))
            revealedHistoryIDs.formIntersection(ids)
            visitedHistoryIDs.formIntersection(ids)
            revealedHistoryIDs.insert(item.id)
            visitedHistoryIDs.insert(item.id)
        } else {
            guard items.count < 50 else { return false }
            items.insert(item, at: min(deletion.index, items.count))
        }
        deletions.removeLast()
        return true
    }
}
