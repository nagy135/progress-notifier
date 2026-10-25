import AppKit
import SwiftUI
import ProgressCore

/// A single animation clock owns row geometry, empty state, mode changes and the window frame.
final class ProgressPresentation: ObservableObject {
    struct Row: Identifiable {
        var item: ProgressItem
        var presence: CGFloat
        var detailsHeight: CGFloat = 64
        var id: UUID { item.id }
    }

    static let transitionDuration: TimeInterval = 0.22
    @Published private(set) var expansion: CGFloat
    @Published private(set) var rows: [Row] = []
    @Published private(set) var emptyPresence: CGFloat = 1
    @Published var maximumHeight: CGFloat = 800
    var geometryChanged: (() -> Void)?
    private var desiredItems: [ProgressItem] = []
    private var targetExpansion: CGFloat
    private var measuredHeights: [UUID: CGFloat] = [:]
    private var timer: Timer?

    init(compact: Bool) {
        expansion = compact ? 0 : 1
        targetExpansion = compact ? 0 : 1
    }

    deinit { timer?.invalidate() }

    var chromeHeight: CGFloat { 36 + 44 * expansion }
    var naturalContentHeight: CGFloat {
        let rowHeight = rows.reduce(CGFloat.zero) { total, row in
            total + row.presence * (20 + (row.detailsHeight + 22) * expansion)
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
        desiredItems = items
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
        let targetEmpty: CGFloat = desiredItems.isEmpty ? 1 : 0
        let targetRows = rows.map { row -> Row in
            var target = row
            target.presence = desiredIDs.contains(row.id) ? 1 : 0
            target.detailsHeight = measuredHeights[row.id] ?? row.detailsHeight
            return target
        }
        let apply: (CGFloat) -> Void = { [weak self] fraction in
            guard let self else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.expansion = startExpansion + (self.targetExpansion - startExpansion) * fraction
                self.emptyPresence = startEmpty + (targetEmpty - startEmpty) * fraction
                self.rows = zip(startRows, targetRows).map { start, target in
                    var row = target
                    row.presence = start.presence + (target.presence - start.presence) * fraction
                    row.detailsHeight = start.detailsHeight + (target.detailsHeight - start.detailsHeight) * fraction
                    return row
                }
                if fraction == 1 {
                    self.rows.removeAll { !desiredIDs.contains($0.id) }
                    self.measuredHeights = self.measuredHeights.filter { desiredIDs.contains($0.key) }
                }
                self.geometryChanged?()
            }
        }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { apply(1); return }
        // Measure new cards at their final text width before allocating any visible space.
        guard rows.allSatisfy({ $0.presence > 0 || measuredHeights[$0.id] != nil || !desiredIDs.contains($0.id) }) else {
            return
        }
        let needsAnimation = startExpansion != targetExpansion || startEmpty != targetEmpty
            || zip(startRows, targetRows).contains { abs($0.presence - $1.presence) > 0.001
                || abs($0.detailsHeight - $1.detailsHeight) > 0.5 }
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
