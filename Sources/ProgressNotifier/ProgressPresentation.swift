import AppKit
import SwiftUI
import ProgressCore

/// A single animation clock owns row geometry, empty state, mode changes and the window frame.
final class ProgressPresentation: ObservableObject {
    struct Row: Identifiable {
        var item: ProgressItem
        var presence: CGFloat
        var detailsHeight: CGFloat = 64
        var historyHeight: CGFloat = 0
        var id: UUID { item.id }
    }

    static let transitionDuration: TimeInterval = 0.22
    @Published private(set) var expansion: CGFloat
    @Published private(set) var rows: [Row] = []
    @Published private(set) var emptyPresence: CGFloat = 1
    @Published private(set) var showsUpdates = false
    @Published private(set) var focusedItemID: UUID?
    @Published private(set) var updatesControlPresence: CGFloat = 0
    @Published var maximumHeight: CGFloat = 800
    var geometryChanged: (() -> Void)?
    private var desiredItems: [ProgressItem] = []
    private var targetExpansion: CGFloat
    private var measuredHeights: [UUID: CGFloat] = [:]
    private var measuredHistoryHeights: [UUID: CGFloat] = [:]
    private var timer: Timer?

    init(compact: Bool) {
        expansion = compact ? 0 : 1
        targetExpansion = compact ? 0 : 1
    }

    deinit { timer?.invalidate() }

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
        let previousIndex = desiredItems.firstIndex(where: { $0.id == focusedItemID }) ?? 0
        desiredItems = items
        if !items.contains(where: { $0.id == focusedItemID }) {
            focusedItemID = items.isEmpty ? nil : items[min(previousIndex, items.count - 1)].id
        }
        if items.isEmpty { showsUpdates = false }
        targetExpansion = compact ? 0 : 1
        let existing = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let desiredIDs = Set(items.map(\.id))
        var nextRows = items.map { item -> Row in
            var row = existing[item.id] ?? Row(item: item, presence: 0)
            row.item = item
            return row
        }
        // Keep departing cards alive until their space and opacity have reached zero.
        for (index, row) in rows.enumerated() where !desiredIDs.contains(row.id) {
            nextRows.insert(row, at: min(index, nextRows.count))
        }
        rows = nextRows
        animate(animated: animated)
    }

    func measure(_ heights: [UUID: CGFloat], animated: Bool) {
        let rowIDs = Set(rows.map(\.id))
        let relevant = heights.filter { rowIDs.contains($0.key) }
        guard relevant.contains(where: { abs((measuredHeights[$0.key] ?? -1) - $0.value) > 0.5 }) else { return }
        measuredHeights.merge(relevant, uniquingKeysWith: { _, new in new })
        animate(animated: animated)
    }

    var focusedItem: ProgressItem? { desiredItems.first { $0.id == focusedItemID } }

    func moveFocus(by offset: Int, animated: Bool) {
        guard !desiredItems.isEmpty else { return }
        let current = desiredItems.firstIndex(where: { $0.id == focusedItemID }) ?? 0
        let next = min(max(0, current + offset), desiredItems.count - 1)
        guard desiredItems[next].id != focusedItemID else { return }
        focusedItemID = desiredItems[next].id
        // When the ledger is open it follows selection, leaving all other rows folded.
        if showsUpdates { animate(animated: animated) }
    }

    func setShowsUpdates(_ shown: Bool, animated: Bool) {
        showsUpdates = shown && focusedItemID != nil
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
            target.historyHeight = showsUpdates && row.id == focusedItemID ? measuredHistoryHeights[row.id] ?? 0 : 0
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
