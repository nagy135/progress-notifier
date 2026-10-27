import AppKit
import SwiftUI
import ProgressCore

enum ThreadGroupSymbol: String, CaseIterable {
    case circle, triangle, square, diamond

    var accessibilityLabel: String { "Shared T3 thread: \(rawValue)" }
}

/// A single animation clock owns row geometry, empty state, mode changes and the window frame.
final class ProgressPresentation: ObservableObject {
    struct Row: Identifiable {
        var item: ProgressItem
        var presence: CGFloat
        var detailsHeight: CGFloat = 64
        var historyHeight: CGFloat = 0
        var threadGroupSymbol: ThreadGroupSymbol?
        var id: UUID { item.id }
    }

    static let transitionDuration: TimeInterval = 0.22
    @Published private(set) var expansion: CGFloat
    @Published private(set) var rows: [Row] = []
    @Published private(set) var emptyPresence: CGFloat = 1
    @Published private(set) var expandedItemIDs: Set<UUID> = []
    @Published private var rememberedItemID: UUID?
    @Published private(set) var isCompact: Bool
    @Published private(set) var updatesControlPresence: CGFloat = 0
    @Published var maximumHeight: CGFloat = 800
    var geometryChanged: (() -> Void)?
    private var desiredItems: [ProgressItem] = []
    private var threadGroupSymbols: [T3ThreadReference: ThreadGroupSymbol] = [:]
    private var targetExpansion: CGFloat
    private var measuredHeights: [UUID: CGFloat] = [:]
    private var measuredHistoryHeights: [UUID: CGFloat] = [:]
    private var timer: Timer?
    private var updatesFollowFocus = false

    init(compact: Bool) {
        isCompact = compact
        expansion = compact ? 0 : 1
        targetExpansion = compact ? 0 : 1
    }

    deinit { timer?.invalidate() }

    // The empty compact card only needs room for its status icon and close button.
    var cardWidth: CGFloat { 200 + 150 * expansion - 128 * emptyPresence * (1 - expansion) }
    var windowWidth: CGFloat { cardWidth + 20 }
    var chromeHeight: CGFloat { 36 + 44 * expansion + 30 * expansion * updatesControlPresence }
    var naturalContentHeight: CGFloat {
        let rowHeight = rows.reduce(CGFloat.zero) { total, row in
            total + row.presence * (20 + (row.detailsHeight + 22 + row.historyHeight) * expansion)
        }
        return rowHeight + rows.indices.reduce(CGFloat.zero) { $0 + spacing(before: $1) }
            + 8 * expansion * (1 - emptyPresence)
            + (20 + 80 * expansion) * emptyPresence
    }
    func spacing(before index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        return (2 + 4 * expansion) * min(rows[index].presence, rows[index - 1].presence)
    }

    var contentHeight: CGFloat { min(naturalContentHeight, max(0, maximumHeight - chromeHeight)) }
    var windowHeight: CGFloat { chromeHeight + contentHeight }
    var needsScrolling: Bool { naturalContentHeight > maximumHeight - chromeHeight + 0.5 }

    func update(items: [ProgressItem], compact: Bool, animated: Bool) {
        isCompact = compact
        let previousIndex = desiredItems.firstIndex(where: { $0.id == rememberedItemID }) ?? 0
        desiredItems = items
        updateThreadGroupSymbols(items)
        if !items.contains(where: { $0.id == rememberedItemID }) {
            rememberedItemID = items.isEmpty ? nil : items[min(previousIndex, items.count - 1)].id
        }
        expandedItemIDs.formIntersection(items.map(\.id))
        if updatesFollowFocus, let rememberedItemID {
            expandedItemIDs = [rememberedItemID]
        }
        if items.isEmpty { updatesFollowFocus = false }
        targetExpansion = compact ? 0 : 1
        let existing = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let desiredIDs = Set(items.map(\.id))
        var nextRows = items.map { item -> Row in
            var row = existing[item.id] ?? Row(item: item, presence: 0)
            row.item = item
            row.threadGroupSymbol = item.t3Thread.flatMap { threadGroupSymbols[$0] }
            return row
        }
        // Keep departing cards alive until their space and opacity have reached zero.
        for (index, var row) in rows.enumerated() where !desiredIDs.contains(row.id) {
            row.threadGroupSymbol = nil
            nextRows.insert(row, at: min(index, nextRows.count))
        }
        rows = nextRows
        animate(animated: animated)
    }

    private func updateThreadGroupSymbols(_ items: [ProgressItem]) {
        let counts = Dictionary(grouping: items.compactMap(\.t3Thread), by: { $0 }).mapValues(\.count)
        // Retain assignments across progress updates, reordering and mode changes.
        // A slot becomes available when fewer than two visible tasks share its thread.
        threadGroupSymbols = threadGroupSymbols.filter { (counts[$0.key] ?? 0) > 1 }
        for item in items {
            guard let thread = item.t3Thread, (counts[thread] ?? 0) > 1,
                  threadGroupSymbols[thread] == nil,
                  let symbol = ThreadGroupSymbol.allCases.first(where: { !threadGroupSymbols.values.contains($0) })
            else { continue }
            threadGroupSymbols[thread] = symbol
        }
    }

    func measure(_ heights: [UUID: CGFloat], animated: Bool) {
        let rowIDs = Set(rows.map(\.id))
        let relevant = heights.filter { rowIDs.contains($0.key) }
        guard relevant.contains(where: { abs((measuredHeights[$0.key] ?? -1) - $0.value) > 0.5 }) else { return }
        measuredHeights.merge(relevant, uniquingKeysWith: { _, new in new })
        animate(animated: animated)
    }

    var focusedItemID: UUID? { rememberedItemID }
    var focusedItem: ProgressItem? { desiredItems.first { $0.id == focusedItemID } }
    var showsUpdates: Bool { focusedItemID.map { expandedItemIDs.contains($0) } ?? false }
    func showsUpdates(for id: UUID) -> Bool { expandedItemIDs.contains(id) }

    func focus(_ id: UUID, animated: Bool) {
        guard desiredItems.contains(where: { $0.id == id }) else { return }
        rememberedItemID = id
        if updatesFollowFocus {
            expandedItemIDs = [id]
            animate(animated: animated)
        }
    }

    func moveFocus(by offset: Int, animated: Bool) {
        guard !desiredItems.isEmpty else { return }
        let current = desiredItems.firstIndex(where: { $0.id == focusedItemID }) ?? 0
        let next = min(max(0, current + offset), desiredItems.count - 1)
        guard desiredItems[next].id != focusedItemID else { return }
        rememberedItemID = desiredItems[next].id
        // A single inspector follows selection; globally opened ledgers keep their state.
        if updatesFollowFocus {
            expandedItemIDs = [desiredItems[next].id]
            animate(animated: animated)
        }
    }

    func setShowsUpdates(_ shown: Bool, animated: Bool) {
        guard let focusedItemID else { return }
        if shown {
            if expandedItemIDs.isEmpty { updatesFollowFocus = true }
            expandedItemIDs.insert(focusedItemID)
        } else {
            expandedItemIDs.remove(focusedItemID)
            if expandedItemIDs.isEmpty { updatesFollowFocus = false }
        }
        animate(animated: animated)
    }

    func toggleAllUpdates(animated: Bool) {
        let eligibleIDs = Set(desiredItems.filter { $0.updates.count > 1 }.map(\.id))
        guard !eligibleIDs.isEmpty else { return }
        updatesFollowFocus = false
        expandedItemIDs = eligibleIDs.isSubset(of: expandedItemIDs) ? [] : eligibleIDs
        animate(animated: animated)
    }

    func measureHistory(_ heights: [UUID: CGFloat], animated: Bool) {
        let ids = Set(rows.map(\.id))
        let relevant = heights.filter { ids.contains($0.key) }
        guard relevant.contains(where: { abs((measuredHistoryHeights[$0.key] ?? -1) - $0.value) > 0.5 }) else { return }
        measuredHistoryHeights.merge(relevant, uniquingKeysWith: { _, new in new })
        animate(animated: animated)
    }

    func rowHeight(_ row: Row) -> CGFloat {
        20 + (row.detailsHeight + 22 + row.historyHeight) * expansion
    }

    private func animate(animated: Bool) {
        timer?.invalidate()
        timer = nil
        let desiredIDs = Set(desiredItems.map(\.id))
        // Invisible rows can take their measured height immediately. Interpolating both
        // height and presence would briefly bulge the window during the empty-state crossfade.
        rows = rows.map { row in
            var row = row
            if row.presence == 0, let height = measuredHeights[row.id] { row.detailsHeight = height }
            return row
        }
        let startRows = rows
        let startExpansion = expansion
        let startEmpty = emptyPresence
        let startControl = updatesControlPresence
        let targetControl: CGFloat = desiredItems.contains(where: { !$0.updates.isEmpty }) ? 1 : 0
        let targetEmpty: CGFloat = desiredItems.isEmpty ? 1 : 0
        let targetRows = rows.map { row -> Row in
            var target = row
            target.presence = desiredIDs.contains(row.id) ? 1 : 0
            target.detailsHeight = measuredHeights[row.id] ?? row.detailsHeight
            target.historyHeight = showsUpdates(for: row.id) ? measuredHistoryHeights[row.id] ?? 0 : 0
            return target
        }
        let apply: (CGFloat) -> Void = { [weak self] fraction in
            guard let self else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.expansion = startExpansion + (self.targetExpansion - startExpansion) * fraction
                self.updatesControlPresence = startControl + (targetControl - startControl) * fraction
                self.emptyPresence = startEmpty + (targetEmpty - startEmpty) * fraction
                self.rows = zip(startRows, targetRows).map { start, target in
                    var row = target
                    row.presence = start.presence + (target.presence - start.presence) * fraction
                    row.historyHeight = start.historyHeight + (target.historyHeight - start.historyHeight) * fraction
                    row.detailsHeight = start.detailsHeight + (target.detailsHeight - start.detailsHeight) * fraction
                    return row
                }
                if fraction == 1 {
                    self.rows.removeAll { !desiredIDs.contains($0.id) }
                    self.measuredHeights = self.measuredHeights.filter { desiredIDs.contains($0.key) }
                    self.measuredHistoryHeights = self.measuredHistoryHeights.filter { desiredIDs.contains($0.key) }
                }
                self.geometryChanged?()
            }
        }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { apply(1); return }
        // Measure new cards at their final text width before allocating any visible space.
        guard rows.allSatisfy({ $0.presence > 0 || measuredHeights[$0.id] != nil || !desiredIDs.contains($0.id) }) else {
            return
        }
        let needsAnimation = startExpansion != targetExpansion || startEmpty != targetEmpty || startControl != targetControl
            || zip(startRows, targetRows).contains { abs($0.presence - $1.presence) > 0.001
                || abs($0.detailsHeight - $1.detailsHeight) > 0.5 || abs($0.historyHeight - $1.historyHeight) > 0.5 }
        guard needsAnimation else { apply(1); return }
        let startedAt = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let fraction = min(1, (ProcessInfo.processInfo.systemUptime - startedAt) / Self.transitionDuration)
            apply(CGFloat(fraction * fraction * (3 - 2 * fraction)))
            if fraction >= 1 {
                timer.invalidate()
                self.timer = nil
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
