import AppKit
import SwiftUI
import ProgressCore

/// Static cards get one initial date without keeping a repeating timer alive.
struct CardTimelineSchedule: TimelineSchedule {
    var interval: TimeInterval
    var paused: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        if paused { return AnySequence([startDate]) }
        return AnySequence(PeriodicTimelineSchedule(from: startDate, by: interval).entries(from: startDate, mode: mode))
    }
}

private struct ButtonFramesKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

private struct ItemFramesKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

private struct ExcludeFromCardClicks: ViewModifier {
    var enabled = true

    func body(content: Content) -> some View {
        content.background(GeometryReader { proxy in
            Color.clear.preference(key: ButtonFramesKey.self, value: enabled ? [proxy.frame(in: .named("progressCard"))] : [])
        })
    }
}

private func remaining(_ seconds: TimeInterval) -> String {
    if seconds <= 0 { return "Finishing soon" }
    let value = Int(ceil(seconds))
    if value < 60 { return "About \(value)s left" }
    if value < 3600 { return "About \(Int(ceil(seconds / 60)))m left" }
    if value < 86400 { return "About \(value / 3600)h \((value % 3600) / 60)m left" }
    return "About \(value / 86400)d \((value % 86400) / 3600)h left"
}

private func added(_ date: Date?, now: Date) -> String {
    guard let date else { return "Added earlier" }
    let seconds = max(0, now.timeIntervalSince(date))
    let value: Int
    let unit: String
    if seconds < 60 {
        value = Int(seconds); unit = "second"
    } else if seconds < 3600 {
        value = Int(seconds / 60); unit = "minute"
    } else if seconds < 86400 {
        value = Int(seconds / 3600); unit = "hour"
    } else {
        value = Int(seconds / 86400); unit = "day"
    }
    return "Added \(value) \(unit)\(value == 1 ? "" : "s") ago"
}

// Light-mode accents need enough contrast against the white panel, rather than
// sharing the luminous mint colors used on dark material.
private struct ProgressPalette {
    let colorScheme: ColorScheme

    var accent: Color {
        colorScheme == .light ? Color(red: 0.04, green: 0.43, blue: 0.37) : .mint
    }

    var warning: Color {
        colorScheme == .light ? Color(red: 0.52, green: 0.31, blue: 0) : Color(red: 0.96, green: 0.75, blue: 0.42)
    }

    func progress(completing: Bool, isChild: Bool = false) -> Color {
        if isChild && !completing { return .purple }
        if colorScheme == .light {
            return completing ? Color(red: 0.09, green: 0.45, blue: 0.28) : accent
        }
        return completing ? .green : Color(red: 0.23, green: 0.72, blue: 0.64)
    }
}

/// Static hatching stays recognizable at compact sizes and with Reduce Motion.
struct WarningStripes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in stride(from: rect.minX - rect.height, through: rect.maxX, by: 6) {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
        }
        return path
    }
}

struct ItemProgressBar: View {
    let item: ProgressItem
    var height: CGFloat = 5

    @Environment(\.colorScheme) private var colorScheme
    private var palette: ProgressPalette { ProgressPalette(colorScheme: colorScheme) }
    private var tint: Color { item.warning == nil ? palette.progress(completing: item.completing, isChild: item.isChild) : palette.warning }

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(colorScheme == .light ? Color.black.opacity(0.12) : tint.opacity(0.13))
                .overlay {
                    if item.warning != nil {
                        WarningStripes().stroke(tint.opacity(0.3), lineWidth: 2).clipShape(Capsule())
                    }
                }
                .overlay(alignment: .leading) {
                    Capsule().fill(tint)
                        .overlay {
                            if item.warning != nil {
                                WarningStripes().stroke(Color.black.opacity(colorScheme == .light ? 0.35 : 0.5), lineWidth: 2)
                                    .clipShape(Capsule())
                            }
                        }
                        .frame(width: proxy.size.width * item.progress / 100)
                }
                .overlay {
                    Capsule().strokeBorder(Color.black.opacity(colorScheme == .light ? 0.16 : 0), lineWidth: 0.5)
                }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .help(item.warning.map { "Warning: \($0)" } ?? item.name)
        .accessibilityValue((item.completing ? "Complete" : "\(Int(item.progress.rounded())) percent")
                            + (item.warning.map { "; Warning: \($0)" } ?? ""))
    }
}

private struct UpdatePulse: ViewModifier {
    let revision: UInt64
    let consumeUpdatePulse: () -> Bool
    let tint: Color
    let cornerRadius: CGFloat
    let borderOpacity: Double
    var scale: CGFloat = 1.035
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var pulseGeneration: UInt64 = 0

    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).fill(tint.opacity(pulse ? 0.18 : 0)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(tint.opacity(pulse ? 0.6 * borderOpacity : 0)))
            .brightness(pulse ? 0.12 : 0)
            .scaleEffect(pulse && !reduceMotion ? scale : 1)
            .onAppear { flashIfNeeded() }
            .onChange(of: revision) { _ in flashIfNeeded() }
    }

    private func flashIfNeeded() {
        guard consumeUpdatePulse() else { return }
        flash()
    }

    private func flash() {
        pulseGeneration &+= 1
        let generation = pulseGeneration
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { pulse = false }
        DispatchQueue.main.async {
            guard pulseGeneration == generation else { return }
            withAnimation(.easeOut(duration: 0.12)) { pulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                guard pulseGeneration == generation else { return }
                withAnimation(.easeInOut(duration: 0.3)) { pulse = false }
            }
        }
    }
}

private func blend(_ compact: CGFloat, _ expanded: CGFloat, _ expansion: CGFloat) -> CGFloat {
    compact + (expanded - compact) * expansion
}

private struct ItemDetailsHeightsKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ItemHistoryHeightsKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private func updateAge(_ date: Date, now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if seconds < 60 { return "Now" }
    if seconds < 3600 { return "\(seconds / 60)m" }
    if seconds < 86400 { return "\(seconds / 3600)h" }
    return "\(seconds / 86400)d"
}

private struct SnapshotMeter: View {
    let progress: Double
    var current = false
    @Environment(\.colorScheme) private var colorScheme
    private var palette: ProgressPalette { ProgressPalette(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { proxy in
                Capsule().fill(palette.accent.opacity(0.13))
                    .overlay(alignment: .leading) {
                        Capsule().fill(palette.accent.opacity(current ? 1 : 0.55))
                            .frame(width: proxy.size.width * progress / 100)
                    }
            }.frame(height: 2)
            Text("\(progress, specifier: "%.0f")%")
                .font(.system(size: 9, weight: .medium)).monospacedDigit()
                .foregroundStyle(palette.accent.opacity(current ? 1 : 0.7))
                .frame(width: 28, alignment: .trailing)
        }
        .frame(height: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recorded progress")
        .accessibilityValue("\(Int(progress.rounded())) percent")
    }
}

private struct SnapshotRow: View {
    let entry: ProgressEntry
    let now: Date
    var latest = false
    var showMeter = true
    @Environment(\.colorScheme) private var colorScheme
    private var palette: ProgressPalette { ProgressPalette(colorScheme: colorScheme) }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(updateAge(entry.recordedAt, now: now))
                .font(.system(size: 8.5, weight: latest ? .medium : .regular)).monospacedDigit()
                .foregroundStyle(latest ? palette.accent : Color.secondary)
                .frame(width: 22, alignment: .leading).padding(.top, 2)
                .accessibilityLabel(entry.recordedAt.formatted(date: .abbreviated, time: .standard))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.description).font(.system(size: 10.5))
                    .foregroundStyle(latest ? Color.primary : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let warning = entry.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10)).foregroundStyle(palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showMeter { SnapshotMeter(progress: entry.progress, current: latest) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ItemCard: View {
    let item: ProgressItem
    let revision: UInt64
    let consumeUpdatePulse: () -> Bool
    let now: Date
    let expansion: CGFloat
    let close: () -> Void
    let detailsHeight: CGFloat
    let historyHeight: CGFloat
    let selected: Bool
    let panelFocused: Bool
    let updatesUnfolded: Bool
    let threadGroupSymbol: ThreadGroupSymbol?
    var titlePresence: CGFloat = 0
    var receipt = false
    var grouped = false
    var detailWidth: CGFloat = ProgressCard.detailsWidth
    var parentLabel: String? = nil

    @Environment(\.colorScheme) private var colorScheme
    private var palette: ProgressPalette { ProgressPalette(colorScheme: colorScheme) }
    private var tint: Color { palette.progress(completing: item.completing, isChild: item.isChild) }
    private var detailOpacity: Double { Double(max(0, (expansion - 0.25) / 0.75)) }
    private var timing: String {
        let estimate = item.completing ? "Complete" : remaining(item.expectedFinish.timeIntervalSince(now))
        return estimate.replacingOccurrences(of: "About ", with: "")
    }

    private var latest: ProgressEntry? { item.updates.first }
    private var earlierUpdateCount: Int { max(0, item.updates.count - 1) }
    private var noteMatchesProgress: Bool { latest?.progress == item.progress }
    private var completionHeaderHeight: CGFloat { item.completing && !receipt ? 24 : 0 }
    private var iconWidth: CGFloat { 22 + (threadGroupSymbol == nil ? 0 : 16) + (item.isChild ? 16 : 0) }

    private var titleIconWidth: CGFloat { 17 + (threadGroupSymbol == nil ? 0 : 13) + (item.isChild ? 13 : 0) }

    private var fullDetails: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let project = item.project, !grouped {
                Text(project).font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary).lineLimit(1)
                    .frame(height: 12).padding(.leading, titleIconWidth).padding(.trailing, 26)
            }
            Text(item.name).font(.system(size: 11.5, weight: .semibold))
                .lineLimit(2).padding(.trailing, 20)
                .padding(.leading, item.project == nil || grouped ? titleIconWidth : 0)
            if let parentLabel, item.isChild {
                Text("↳ \(parentLabel)").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            if let latest {
                HStack(alignment: .top, spacing: 6) {
                    Text(latest.description).font(.system(size: 10.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(updateAge(latest.recordedAt, now: now))
                        .font(.system(size: 8.5)).monospacedDigit().foregroundStyle(palette.accent)
                        .padding(.top, 2)
                        .accessibilityLabel(latest.recordedAt.formatted(date: .abbreviated, time: .standard))
                }
                if !noteMatchesProgress {
                    Text("Current progress · last note at \(latest.progress, specifier: "%.0f")%")
                        .font(.system(size: 9)).foregroundStyle(.secondary).padding(.top, 5)
                }
            }
            if let warning = item.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                    .accessibilityLabel("Warning: \(warning)")
            }
        }
        // Measure at the final text width, and center completion over the whole card.
        .frame(width: detailWidth, alignment: .leading)
        .padding(.top, completionHeaderHeight)
        .overlay(alignment: .top) {
            if item.completing {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white, palette.progress(completing: true))
                    .accessibilityLabel("Completed")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var details: some View {
        Group {
            if receipt {
                Text(item.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    .padding(.leading, titleIconWidth + 6).padding(.trailing, 20)
                    .frame(width: detailWidth, alignment: .leading)
            } else { fullDetails }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ItemDetailsHeightsKey.self, value: [item.id: proxy.size.height])
        })
    }

    private var earlierUpdates: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(item.updates.dropFirst()) { entry in
                Divider().padding(.vertical, 4)
                SnapshotRow(entry: entry, now: now)
            }
        }
        .frame(width: detailWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ItemHistoryHeightsKey.self, value: [item.id: proxy.size.height])
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            details
                .frame(width: 0, height: detailsHeight * expansion, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(detailOpacity).clipped()
                .accessibilityHidden(expansion < 0.5)
                .padding(.bottom, (receipt ? 2 : 3) * expansion)
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: blend(iconWidth, earlierUpdateCount > 0 ? 22 : 0, expansion), height: blend(16, 12, expansion))
                    .overlay(alignment: .leading) {
                        if earlierUpdateCount > 0 && !receipt {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                                Text("\(earlierUpdateCount)").font(.system(size: 8, weight: .medium)).monospacedDigit()
                            }
                            .foregroundStyle(.secondary)
                            .opacity(updatesUnfolded || historyHeight > 0.5 ? 0 : detailOpacity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(earlierUpdateCount) earlier updates")
                            .accessibilityHidden(updatesUnfolded || historyHeight > 0.5 || expansion < 0.5)
                        }
                    }
                HStack(spacing: 4) {
                    if item.isChild {
                        Text("Child").font(.system(size: 8, weight: .semibold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.primary.opacity(0.07), in: Capsule())
                            .accessibilityLabel("Child delegate task")
                    }
                    Text(timing).font(.system(size: 9)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                .foregroundStyle(.secondary)
                .frame(width: receipt ? 0 : (item.isChild ? 106 : 76) * expansion,
                       alignment: .leading)
                .opacity(detailOpacity).clipped()
                .accessibilityHidden(receipt || expansion < 0.5)
                Text(item.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1).truncationMode(.tail)
                    .frame(width: 105 * titlePresence, alignment: .leading)
                    .padding(.trailing, 7 * titlePresence)
                    .opacity(Double(titlePresence)).clipped()
                    .accessibilityHidden(titlePresence < 0.5)
                ItemProgressBar(item: item, height: blend(5, 3, expansion))
                    .opacity(item.completing ? Double(expansion) : 1)
                    .accessibilityHidden(item.completing && expansion < 0.5)
                    .overlay {
                        if item.completing {
                            let statusTint = item.warning == nil ? tint : palette.warning
                            Text("Done")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(statusTint)
                                .frame(maxWidth: .infinity)
                                .frame(height: 14)
                                .background(statusTint.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
                                .overlay {
                                    if item.warning != nil {
                                        WarningStripes().stroke(statusTint.opacity(0.3), lineWidth: 2)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                                .opacity(Double(1 - expansion))
                                .accessibilityLabel("\(item.name), completed")
                                .accessibilityValue(item.warning.map { "Warning: \($0)" } ?? "")
                                .accessibilityHidden(expansion >= 0.5)
                        }
                    }
                // Reserve the same trailing space on every compact row so selecting
                // a task never shifts its bar. Inset the dot from the selection
                // outline as well as from the progress bar.
                Circle().fill(tint)
                    .frame(width: 5, height: 5)
                    .opacity(selected ? (panelFocused ? 1 : 0.6) * Double(1 - expansion) : 0)
                    .frame(width: 5 * (1 - expansion)).clipped()
                    .padding(.leading, 6 * (1 - expansion))
                    .padding(.trailing, 6 * (1 - expansion))
                    .allowsHitTesting(false).accessibilityHidden(true)
                Text("\(item.progress, specifier: "%.0f")%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit().foregroundStyle(tint)
                    .frame(width: receipt ? 0 : 28 * expansion, alignment: .trailing)
                    .padding(.leading, receipt ? 0 : 8 * expansion)
                    .opacity(receipt ? 0 : detailOpacity).clipped()
                    .accessibilityHidden(expansion < 0.5)
            }
            .frame(height: blend(ProgressCard.compactRowHeight, receipt ? 4 : 12, expansion))
            // A zero-height frame still builds and lays out every snapshot. Mount the
            // ledger on demand, retaining it until a closing animation has finished.
            if updatesUnfolded || historyHeight > 0 {
                earlierUpdates
                    .frame(width: 0, height: historyHeight * expansion, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(detailOpacity).clipped()
                    .accessibilityElement(children: historyHeight < 0.5 ? .ignore : .contain)
                    .accessibilityHidden(historyHeight < 0.5 || expansion < 0.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8 * expansion)
        .padding(.vertical, (receipt ? 6 : 5) * expansion)
        .overlay(alignment: .topLeading) {
            HStack(spacing: blend(4, 3, expansion)) {
                if receipt {
                    ZStack {
                        ProjectIconView(project: item.project ?? item.name, icon: item.projectIcon, size: blend(16, 13, expansion))
                            .opacity(Double(1 - expansion))
                            .accessibilityHidden(expansion >= 0.5)
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(tint)
                            .opacity(Double(expansion))
                            .accessibilityLabel("Completed")
                            .accessibilityHidden(expansion < 0.5)
                    }
                    .frame(width: blend(16, 18, expansion), height: 16)
                } else {
                    ProjectIconView(project: item.project ?? item.name, icon: item.projectIcon, size: blend(16, 13, expansion))
                }
                if item.isChild {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: blend(12, 10, expansion), height: blend(16, 13, expansion))
                        .accessibilityLabel("Child delegate task")
                }
                if let threadGroupSymbol {
                    Image(systemName: threadGroupSymbol.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: blend(12, 10, expansion), height: blend(16, 13, expansion))
                        .accessibilityLabel(threadGroupSymbol.accessibilityLabel)
                }
            }
                .padding(.leading, 8 * expansion)
                .padding(.top, blend((ProgressCard.compactRowHeight - 16) / 2, (receipt ? 6 : 5) + completionHeaderHeight, expansion))
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary).frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(item.name)")
            .modifier(ExcludeFromCardClicks(enabled: expansion > 0.95))
            .padding(.trailing, 2 * expansion).padding(.top, 0)
            .opacity(detailOpacity).allowsHitTesting(expansion > 0.95)
            .accessibilityHidden(expansion < 0.5)
        }
        .background(.primary.opacity(0.035 * expansion), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            if item.isChild && grouped {
                RoundedRectangle(cornerRadius: blend(4, 6, expansion))
                    .strokeBorder(Color.purple.opacity(0.3 * Double(expansion)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .allowsHitTesting(false)
            }
        }
        .modifier(UpdatePulse(revision: revision, consumeUpdatePulse: consumeUpdatePulse,
                              tint: tint, cornerRadius: blend(4, 6, expansion),
                              borderOpacity: Double(expansion),
                              scale: 1 + 0.035 * expansion))
        .overlay {
            RoundedRectangle(cornerRadius: blend(4, 6, expansion))
                .fill(palette.accent.opacity(selected ? 0.055 * Double(expansion) : 0))
                .overlay {
                    RoundedRectangle(cornerRadius: blend(4, 6, expansion))
                        .strokeBorder(palette.accent.opacity(selected ? (panelFocused ? 0.9 : 0.6) * Double(expansion) : 0))
                }
                .allowsHitTesting(false)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help("\(timing) · \(added(item.createdAt, now: now))")

    }
}

private struct TimelineRail: View {
    let depth: Int
    let endsGroup: Bool
    let continuesBelow: Bool
    let expansion: CGFloat
    let rowHeight: CGFloat

    var body: some View {
        Canvas { context, _ in
            let mainX: CGFloat = 5
            let nodeY: CGFloat = 10 + 4 * expansion
            let bottom = rowHeight + (endsGroup ? 0 : 2 + expansion)
            var rail = Path()
            rail.move(to: CGPoint(x: mainX, y: 0))
            rail.addLine(to: CGPoint(x: mainX, y: endsGroup ? nodeY : bottom))
            context.stroke(rail, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
            if depth > 0 {
                let branchX = 5 + CGFloat(min(depth, 2)) * 12
                var branch = Path()
                branch.move(to: CGPoint(x: branchX, y: 0))
                branch.addLine(to: CGPoint(x: branchX, y: nodeY))
                branch.addLine(to: CGPoint(x: branchX + 7, y: nodeY))
                context.stroke(branch, with: .color(.purple.opacity(0.65)), lineWidth: 1)
            } else {
                context.stroke(Path(ellipseIn: CGRect(x: mainX - 2.5, y: nodeY - 2.5, width: 5, height: 5)),
                               with: .color(.mint.opacity(0.8)), lineWidth: 1)
            }
            if continuesBelow {
                let y = rowHeight - 2
                var arrow = Path()
                arrow.move(to: CGPoint(x: mainX - 3, y: y - 3))
                arrow.addLine(to: CGPoint(x: mainX, y: y))
                arrow.addLine(to: CGPoint(x: mainX + 3, y: y - 3))
                context.stroke(arrow, with: .color(.mint), lineWidth: 1)
            }
        }
        .frame(width: 44, height: max(0, rowHeight + (endsGroup ? 0 : 2 + expansion)), alignment: .topLeading)
    }
}

struct ProgressCard: View {
    static let compactRowHeight: CGFloat = 20
    static let compactRowSpacing: CGFloat = 2
    // Reserve the native legacy scroller gutter even before overflow, so descriptions
    // never rewrap and historical percentages never clip when macOS shows the scroller.
    static let expandedRowWidth: CGFloat = 334 - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    static let detailsWidth: CGFloat = expandedRowWidth - 16

    @ObservedObject var model: ProgressModel
    @ObservedObject var presentation: ProgressPresentation
    let detailsHeightsChanged: ([UUID: CGFloat]) -> Void
    let historyHeightsChanged: ([UUID: CGFloat]) -> Void
    let toggleUpdates: () -> Void
    let toggleCompact: () -> Void
    let openFocusedThread: () -> Void
    let close: () -> Void
    @State private var buttonFrames: [CGRect] = []
    @State private var itemFrames: [CGRect] = []
    @State private var focusScrollGeneration = 0
    @Environment(\.colorScheme) private var colorScheme
    private var palette: ProgressPalette { ProgressPalette(colorScheme: colorScheme) }

    private var expansion: CGFloat { presentation.expansion }

    static func horizontalInset(expansion: CGFloat) -> CGFloat { blend(12, 14, expansion) }
    static func verticalInset(expansion: CGFloat) -> CGFloat { blend(8, 12, expansion) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Progress")
                .frame(height: 18 * expansion, alignment: .center)
                .opacity(Double(expansion)).clipped()
                .padding(.bottom, 4 * expansion)
                .accessibilityHidden(expansion < 0.5)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: presentation.needsScrolling) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(presentation.rows.enumerated()), id: \.element.id) { index, row in
                            timelineRow(row)
                                .frame(width: blend(presentation.compactRowWidth, Self.expandedRowWidth, expansion), alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(height: presentation.rowHeight(row) * row.presence,
                                       alignment: .top)
                                .opacity(Double(row.presence)).clipped()
                                .accessibilityHidden(row.presence < 0.5)
                                .contentShape(Rectangle())
                                .simultaneousGesture(SpatialTapGesture(count: 2, coordinateSpace: .named("progressCard")).onEnded { value in
                                    selectItem(row.id, at: value.location, openThread: true)
                                })
                                .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named("progressCard")).onEnded { value in
                                    selectItem(row.id, at: value.location, openThread: false)
                                })
                                .background(GeometryReader { proxy in
                                    Color.clear.preference(key: ItemFramesKey.self,
                                        value: row.presence > 0.95 ? [proxy.frame(in: .named("progressCard"))] : [])
                                })
                                .allowsHitTesting(row.presence > 0.95)
                                .padding(.top, presentation.spacing(before: index))
                                .overlay(alignment: .topLeading) {
                                    if row.timeline != nil && row.timeline?.startsGroup == false {
                                        Rectangle().fill(.secondary.opacity(0.3))
                                            .frame(width: 1, height: presentation.spacing(before: index))
                                            .offset(x: 4.5).allowsHitTesting(false).accessibilityHidden(true)
                                    }
                                }
                                .id(row.id)
                        }
                        emptyState
                            .frame(height: 20 + 80 * expansion)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(height: (20 + 80 * expansion) * presentation.emptyPresence, alignment: .top)
                            .opacity(Double(presentation.emptyPresence)).clipped()
                            .accessibilityHidden(presentation.emptyPresence < 0.5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4 * expansion * (1 - presentation.emptyPresence))
                    .padding(.horizontal, 4 * expansion)
                    .frame(height: presentation.naturalContentHeight, alignment: .top)
                }
                .scrollDisabled(!presentation.needsScrolling)
                .padding(.trailing, 32 * (1 - expansion))
                .frame(height: presentation.contentHeight, alignment: .top)
                .clipped()
                .onChange(of: presentation.focusedItemID) { _ in revealFocus(using: proxy) }
                .onChange(of: presentation.showsUpdates) { _ in revealFocus(using: proxy) }
            }

            HStack {
                Button(action: toggleUpdates) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text(presentation.showsUpdates ? "Hide earlier updates" : "Show updates")
                        Text("D").font(.system(size: 9)).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                .buttonStyle(.plain).modifier(ExcludeFromCardClicks(enabled: expansion > 0.95 && presentation.updatesControlPresence > 0.95))
                .disabled(presentation.focusedItem?.updates.isEmpty != false)
                .accessibilityLabel(presentation.showsUpdates ? "Hide earlier updates for focused task" : "Show updates for focused task")
                Spacer()
                Text("↑↓  J/K").font(.system(size: 9))
            }
            .font(.system(size: 9)).foregroundStyle(.secondary)
            .frame(height: 18 * expansion * presentation.updatesControlPresence, alignment: .bottom)
            .opacity(Double(expansion * presentation.updatesControlPresence)).clipped()
            .allowsHitTesting(expansion > 0.95 && presentation.updatesControlPresence > 0.95)
            .accessibilityHidden(expansion < 0.5 || presentation.updatesControlPresence < 0.5)
        }
        .padding(.horizontal, Self.horizontalInset(expansion: expansion))
        .padding(.vertical, Self.verticalInset(expansion: expansion))
        .frame(width: presentation.cardWidth)
        .background {
            RoundedRectangle(cornerRadius: 20).fill(.regularMaterial)
                .overlay {
                    // Keep dark windows and games from turning light mode gray.
                    if colorScheme == .light {
                        RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.80))
                    }
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 20).fill(palette.accent.opacity(model.isFocused ? 0.06 * Double(expansion) : 0))
            .allowsHitTesting(false))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .strokeBorder(model.isFocused ? palette.accent.opacity(0.9) : .primary.opacity(colorScheme == .light ? 0.22 : 0.08),
                          lineWidth: model.isFocused ? 1 + expansion : 1)
            .opacity(model.isFocused || colorScheme == .light ? 1 : Double(expansion))
            .allowsHitTesting(false))
        // A single, fixed-size control stays anchored to the same corner in both modes.
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary).frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close progress window")
            .modifier(ExcludeFromCardClicks())
            .padding(.horizontal, Self.horizontalInset(expansion: expansion))
            // Keep the X centered on the first compact row despite its larger hit area.
            .padding(.top, Self.verticalInset(expansion: expansion)
                     + (Self.compactRowHeight - 24) / 2 * (1 - expansion) - 3 * expansion)
        }
        .padding(10)
        .coordinateSpace(name: "progressCard")
        .onPreferenceChange(ButtonFramesKey.self) { buttonFrames = $0 }
        .onPreferenceChange(ItemFramesKey.self) { itemFrames = $0 }
        .onPreferenceChange(ItemDetailsHeightsKey.self) { heights in
            DispatchQueue.main.async { detailsHeightsChanged(heights) }
        }
        .onPreferenceChange(ItemHistoryHeightsKey.self) { heights in
            DispatchQueue.main.async { historyHeightsChanged(heights) }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(SpatialTapGesture().onEnded { value in
            // Only the top chrome changes mode; blank space beside/below tasks does not.
            let topHeight = 10 + Self.verticalInset(expansion: expansion) + 22 * expansion
            if value.location.y < topHeight,
               !(buttonFrames + itemFrames).contains(where: { $0.contains(value.location) }) {
                toggleCompact()
            }
        })
    }

    private func timelineRow(_ row: ProgressPresentation.Row) -> some View {
        let inset = ProgressPresentation.timelineInset(row)
        let width = Self.expandedRowWidth - inset
        return VStack(alignment: .leading, spacing: 0) {
            if row.timeline?.startsGroup == true {
                HStack(spacing: 6) {
                    ProjectIconView(project: row.item.project ?? row.item.name, icon: row.item.projectIcon, size: 13)
                    Text(row.item.project ?? "T3 chat").font(.system(size: 10, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(String(row.item.t3Thread?.threadId.suffix(6) ?? ""))
                        .font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                }
                .frame(height: presentation.headerHeight(row), alignment: .top)
                .opacity(Double(expansion)).clipped().accessibilityHidden(expansion < 0.5)
            }
            // Clock invalidations stay inside a card, rather than relaying out the
            // whole stack every second. Receipts and compact bars have no live text.
            TimelineView(CardTimelineSchedule(interval: row.item.completing ? 60 : 1,
                                              paused: expansion == 0 || row.receipt)) { context in
                itemCard(row, now: context.date, width: width)
            }
                .padding(.leading, inset)
                .overlay(alignment: .topLeading) {
                    if let entry = row.timeline {
                        TimelineRail(depth: entry.depth, endsGroup: entry.endsGroup,
                                     continuesBelow: entry.continuesBelow, expansion: expansion,
                                     rowHeight: presentation.rowHeight(row) - presentation.headerHeight(row))
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
        }
        .help(row.item.name + (row.timeline?.parentLabel.map { " · Child of " + $0 } ?? ""))
    }

    private func itemCard(_ row: ProgressPresentation.Row, now: Date, width: CGFloat) -> some View {
        ItemCard(item: row.item, revision: model.revision(for: row.item),
                 consumeUpdatePulse: { model.consumeUpdatePulse(for: row.item) },
                 now: now, expansion: expansion,
                 close: { model.close(row.item) }, detailsHeight: row.detailsHeight,
                 historyHeight: row.historyHeight,
                 selected: presentation.focusedItemID == row.id, panelFocused: model.isFocused,
                 updatesUnfolded: presentation.showsUpdates(for: row.id),
                 threadGroupSymbol: row.threadGroupSymbol, titlePresence: presentation.titlePresence, receipt: row.receipt,
                 grouped: row.timeline != nil, detailWidth: width - 16,
                 parentLabel: row.timeline?.detached == true ? row.timeline?.parentLabel : nil)
    }

    private func selectItem(_ id: UUID, at point: CGPoint, openThread: Bool) {
        guard !buttonFrames.contains(where: { $0.contains(point) }) else { return }
        presentation.focus(id, animated: true)
        guard presentation.focusedItemID == id else { return }
        if openThread { openFocusedThread() }
    }

    private func revealFocus(using proxy: ScrollViewProxy) {
        focusScrollGeneration += 1
        let generation = focusScrollGeneration
        guard let id = presentation.focusedItemID else { return }
        let anchor: UnitPoint? = presentation.showsUpdates ? .top : nil
        // Resolve against the new row layout, then once more when native resizing ends.
        // This only follows keyboard selection/detail actions, not background progress updates.
        DispatchQueue.main.async {
            guard generation == focusScrollGeneration, presentation.focusedItemID == id else { return }
            proxy.scrollTo(id, anchor: anchor)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ProgressPresentation.transitionDuration + 0.03) {
            guard generation == focusScrollGeneration, presentation.focusedItemID == id else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                proxy.scrollTo(id, anchor: anchor)
            } else {
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: anchor) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8 * expansion) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: blend(16, 26, expansion), weight: .light))
                .foregroundStyle(palette.accent)
            Text("No progress").font(.system(size: 14, weight: .medium))
                .frame(height: 17 * expansion).opacity(Double(expansion)).clipped()
            Text(model.hasHistory ? "Press H to recall a completed result" : "Waiting for tasks…")
                .font(.system(size: 9)).foregroundStyle(.secondary)
                .frame(height: 14 * expansion).opacity(Double(expansion)).clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}
