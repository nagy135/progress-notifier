import Foundation

/// Visible projection only: history recall, closing and deletion remain registry concerns.
public enum ChatTimeline {
    public struct Entry {
        public let item: ProgressItem
        public let depth: Int
        public let startsGroup: Bool
        public let endsGroup: Bool
        public let continuesBelow: Bool
        public let parentLabel: String?
        public let detached: Bool
    }

    private enum Group: Hashable {
        case chat(T3ThreadReference)
        case standalone(UUID)
    }

    public static func entries(visible: [ProgressItem], retained: [ProgressItem] = []) -> [Entry] {
        var seen = Set<UUID>()
        let all = (retained + visible).filter { seen.insert($0.id).inserted }
        let positions = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($0.element.id, $0.offset) })
        func older(_ a: ProgressItem, _ b: ProgressItem) -> Bool {
            if a.createdAt != b.createdAt {
                return (a.createdAt ?? .distantPast) < (b.createdAt ?? .distantPast)
            }
            let lhs = a.creationOrder ?? 0, rhs = b.creationOrder ?? 0
            if lhs != rhs { return lhs < rhs }
            return (positions[a.id] ?? 0) < (positions[b.id] ?? 0)
        }
        func key(_ item: ProgressItem) -> Group {
            item.t3Thread.map(Group.chat) ?? .standalone(item.id)
        }
        var groupOrder: [Group] = []
        var grouped: [Group: [ProgressItem]] = [:]
        for item in visible where grouped[key(item)]?.contains(where: { $0.id == item.id }) != true {
            let group = key(item)
            if grouped[group] == nil { groupOrder.append(group) }
            grouped[group, default: []].append(item)
        }
        // Retained (including hidden) records anchor a group's rank without revealing any rows.
        var anchors: [Group: ProgressItem] = [:]
        for item in all {
            let group = key(item)
            if anchors[group] == nil || older(item, anchors[group]!) { anchors[group] = item }
        }
        groupOrder.sort { older(anchors[$0]!, anchors[$1]!) }
        var result: [Entry] = []
        for group in groupOrder {
            let members = grouped[group]!.sorted(by: older)
            // Unlinked clients keep standalone rows; isChild still supplies the role marker.
            guard case .chat = group else {
                result += members.map { Entry(item: $0, depth: 0, startsGroup: false, endsGroup: true,
                                              continuesBelow: false, parentLabel: nil, detached: false) }
                continue
            }
            var runs: [UUID: ProgressItem] = [:]
            for item in members { if let id = item.runId { runs[id] = item } }
            var children: [UUID: [ProgressItem]] = [:]
            for item in members where item.isChild {
                if let parent = item.parentRunId, let owner = runs[parent], owner.id != item.id {
                    children[owner.id, default: []].append(item)
                }
            }
            let attached = Set(children.values.flatMap { $0 }.map(\.id))
            let mains = members.filter { !$0.isChild }
            let detached = members.filter { $0.isChild && !attached.contains($0.id) }
            var ordered: [(ProgressItem, Int, String?, Bool)] = []
            var visited = Set<UUID>()
            func append(_ item: ProgressItem, depth: Int, parent: String?, detached: Bool) {
                guard visited.insert(item.id).inserted else { return }
                ordered.append((item, depth, parent, detached))
                for child in children[item.id] ?? [] {
                    append(child, depth: depth + 1, parent: item.name, detached: false)
                }
            }
            for main in mains { append(main, depth: 0, parent: nil, detached: false) }
            for child in detached {
                append(child, depth: 1, parent: child.parentRunId == nil ? "Parent unspecified" : "Parent not visible", detached: true)
            }
            // Corrupt legacy graphs must not make tasks disappear.
            for item in members where !visited.contains(item.id) {
                append(item, depth: 1, parent: "Parent unavailable", detached: true)
            }
            for (index, row) in ordered.enumerated() {
                // Arrow at the end of a main's subtree, pointing toward the next main.
                let continuation = index + 1 < ordered.count && ordered[index + 1].1 == 0
                result.append(Entry(item: row.0, depth: row.1, startsGroup: index == 0,
                                    endsGroup: index == ordered.count - 1, continuesBelow: continuation,
                                    parentLabel: row.2, detached: row.3))
            }
        }
        return result
    }
}
