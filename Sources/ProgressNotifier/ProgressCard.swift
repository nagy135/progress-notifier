import AppKit
import SwiftUI
import ProgressCore

private struct ButtonFramesKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

private struct ExcludeFromToggle: ViewModifier {
    func body(content: Content) -> some View {
        content.background(GeometryReader { proxy in
            Color.clear.preference(key: ButtonFramesKey.self, value: [proxy.frame(in: .named("progressCard"))])
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

    func progress(completing: Bool) -> Color {
        if colorScheme == .light {
            return completing ? Color(red: 0.09, green: 0.45, blue: 0.28) : accent
        }
        return completing ? .green : Color(red: 0.23, green: 0.72, blue: 0.64)
    }
}

private struct ItemProgressBar: View {
    let item: ProgressItem

    @Environment(\.colorScheme) private var colorScheme
    private var palette: ProgressPalette { ProgressPalette(colorScheme: colorScheme) }
    private var tint: Color { palette.progress(completing: item.completing) }

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(colorScheme == .light ? Color.black.opacity(0.12) : tint.opacity(0.13))
                .overlay(alignment: .leading) {
                    Capsule().fill(tint).frame(width: proxy.size.width * item.progress / 100)
                }
                .overlay {
                    Capsule().strokeBorder(Color.black.opacity(colorScheme == .light ? 0.16 : 0), lineWidth: 0.5)
                }
        }
        .frame(height: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(item.completing ? "Complete" : "\(Int(item.progress.rounded())) percent")
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
            }.frame(height: 4)
            Text("\(progress, specifier: "%.0f")%")
                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                .foregroundStyle(palette.accent.opacity(current ? 1 : 0.7))
                .frame(width: 34, alignment: .trailing)
        }
        .frame(height: 14)
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
        HStack(alignment: .top, spacing: 8) {
            Text(updateAge(entry.recordedAt, now: now))
                .font(.system(size: 9, weight: latest ? .medium : .regular)).monospacedDigit()
                .foregroundStyle(latest ? palette.accent : Color.secondary)
                .frame(width: 30, alignment: .leading).padding(.top, 2)
                .accessibilityLabel(entry.recordedAt.formatted(date: .abbreviated, time: .standard))
            VStack(alignment: .leading, spacing: 7) {
                Text(entry.description).font(.system(size: 12))
                    .foregroundStyle(latest ? Color.primary : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
    let dismiss: () -> Void
    let detailsHeight: CGFloat
    let historyHeight: CGFloat
    let selected: Bool
    let panelFocused: Bool
    let updatesUnfolded: Bool

    @Environment(\.colorScheme) private var colorScheme
    private var palette: ProgressPalette { ProgressPalette(colorScheme: colorScheme) }
    private var tint: Color { palette.progress(completing: item.completing) }
    private var detailOpacity: Double { Double(max(0, (expansion - 0.25) / 0.75)) }
    private var timing: String {
        let estimate = item.completing ? "Complete" : remaining(item.expectedFinish.timeIntervalSince(now))
        return "\(estimate) · \(added(item.createdAt, now: now))"
    }

    private var latest: ProgressEntry? { item.updates.first }
    private var earlierUpdateCount: Int { max(0, item.updates.count - 1) }
    private var noteMatchesProgress: Bool { latest?.progress == item.progress }
    private var completionHeaderHeight: CGFloat { item.completing ? 32 : 0 }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let project = item.project {
                Text(project).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary).lineLimit(1)
                    .frame(height: 16).padding(.leading, 22)
            }
            Text(item.name).font(.system(size: 13, weight: .semibold))
                .lineLimit(2).padding(.trailing, 30)
                .padding(.leading, item.project == nil ? 22 : 0)
            Text(timing).lineLimit(1).minimumScaleFactor(0.8)
                .font(.system(size: latest == nil ? 11 : 10)).foregroundStyle(.secondary).monospacedDigit()
                .padding(.leading, item.project == nil && latest == nil ? 22 : 0)
            if let latest {
                SnapshotRow(entry: latest, now: now, latest: true, showMeter: !noteMatchesProgress)
                    .padding(.top, 8)
                if !noteMatchesProgress {
                    Text("Current progress · last note at \(latest.progress, specifier: "%.0f")%")
                        .font(.system(size: 9)).foregroundStyle(.secondary).padding(.top, 5)
                }
            }
        }
        // Measure at the final text width, and center completion over the whole card.
        .frame(width: ProgressCard.detailsWidth, alignment: .leading)
        .padding(.top, completionHeaderHeight)
        .overlay(alignment: .top) {
            if item.completing {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white, palette.progress(completing: true))
                    .accessibilityLabel("Completed")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ItemDetailsHeightsKey.self, value: [item.id: proxy.size.height])
        })
    }

    private var earlierUpdates: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(item.updates.dropFirst()) { entry in
                Divider().padding(.vertical, 10)
                SnapshotRow(entry: entry, now: now)
            }
        }
        .frame(width: ProgressCard.detailsWidth, alignment: .leading)
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
                .padding(.bottom, 8 * expansion)
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: blend(22, latest == nil ? 0 : 38, expansion), height: 16)
                    .overlay(alignment: .leading) {
                        if earlierUpdateCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                                Text("\(earlierUpdateCount)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                            }
                            .foregroundStyle(.secondary)
                            .opacity(updatesUnfolded || historyHeight > 0.5 ? 0 : detailOpacity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(earlierUpdateCount) earlier updates")
                            .accessibilityHidden(updatesUnfolded || historyHeight > 0.5 || expansion < 0.5)
                        }
                    }
                ItemProgressBar(item: item)
                Text("\(item.progress, specifier: "%.0f")%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit().foregroundStyle(tint)
                    .frame(width: 38 * expansion, alignment: .trailing)
                    .padding(.leading, 8 * expansion)
                    .opacity(detailOpacity).clipped()
                    .accessibilityHidden(expansion < 0.5)
            }
            .frame(height: blend(ProgressCard.compactRowHeight, 16, expansion))
            earlierUpdates
                .frame(width: 0, height: historyHeight * expansion, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(detailOpacity).clipped()
                .accessibilityElement(children: historyHeight < 0.5 ? .ignore : .contain)
                .accessibilityHidden(historyHeight < 0.5 || expansion < 0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12 * expansion)
        .padding(.vertical, 9 * expansion)
        .overlay(alignment: .topLeading) {
            ProjectIconView(project: item.project ?? item.name, icon: item.projectIcon)
                .padding(.leading, 12 * expansion)
                .padding(.top, blend((ProgressCard.compactRowHeight - 16) / 2, 9 + completionHeaderHeight, expansion))
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary).frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss \(item.name)")
            .modifier(ExcludeFromToggle())
            .padding(.trailing, 12 * expansion).padding(.top, 9 * expansion)
            .opacity(detailOpacity).allowsHitTesting(expansion > 0.95)
            .accessibilityHidden(expansion < 0.5)
        }
        .background(.primary.opacity(0.035 * expansion), in: RoundedRectangle(cornerRadius: 12))
        .modifier(UpdatePulse(revision: revision, consumeUpdatePulse: consumeUpdatePulse,
                              tint: tint, cornerRadius: blend(4, 12, expansion),
                              borderOpacity: Double(expansion),
                              scale: 1 + 0.035 * expansion))
        .overlay {
            RoundedRectangle(cornerRadius: blend(4, 12, expansion))
                .fill(palette.accent.opacity(selected ? 0.055 * Double(expansion) : 0))
                .overlay {
                    RoundedRectangle(cornerRadius: blend(4, 12, expansion))
                        .strokeBorder(palette.accent.opacity(selected ? (panelFocused ? 0.9 : 0.6) * Double(expansion) : 0))
                }
                .allowsHitTesting(false)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])

    }
}

struct ProgressCard: View {
    static let compactRowHeight: CGFloat = 20
    static let compactRowSpacing: CGFloat = 2
    // Reserve the native legacy scroller gutter even before overflow, so descriptions
    // never rewrap and historical percentages never clip when macOS shows the scroller.
    static let expandedRowWidth: CGFloat = 314 - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    static let detailsWidth: CGFloat = expandedRowWidth - 24

    @ObservedObject var model: ProgressModel
    @ObservedObject var presentation: ProgressPresentation
    let detailsHeightsChanged: ([UUID: CGFloat]) -> Void
    let historyHeightsChanged: ([UUID: CGFloat]) -> Void
    let toggleUpdates: () -> Void
    let toggleCompact: () -> Void
    let close: () -> Void
    @State private var buttonFrames: [CGRect] = []
    @State private var focusScrollGeneration = 0
    @Environment(\.colorScheme) private var colorScheme
    private var palette: ProgressPalette { ProgressPalette(colorScheme: colorScheme) }

    private var expansion: CGFloat { presentation.expansion }
    private var runningCount: Int { model.items.filter { !$0.completing }.count }

    static func horizontalInset(expansion: CGFloat) -> CGFloat { blend(12, 14, expansion) }
    static func verticalInset(expansion: CGFloat) -> CGFloat { blend(8, 14, expansion) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Progress").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("\(runningCount) active")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.primary.opacity(0.05), in: Capsule())
            }
            .padding(.trailing, 32)
            .frame(height: 24 * expansion, alignment: .top)
            .opacity(Double(expansion)).clipped()
            .padding(.bottom, 8 * expansion)
            .accessibilityHidden(expansion < 0.5)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: presentation.needsScrolling) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(presentation.rows.enumerated()), id: \.element.id) { index, row in
                                ItemCard(item: row.item, revision: model.revision(for: row.item),
                                         consumeUpdatePulse: { model.consumeUpdatePulse(for: row.item) },
                                         now: context.date, expansion: expansion,
                                         dismiss: { model.dismiss(row.item) }, detailsHeight: row.detailsHeight,
                                         historyHeight: row.historyHeight,
                                         selected: presentation.focusedItemID == row.id, panelFocused: model.isFocused,
                                         updatesUnfolded: presentation.showsUpdates(for: row.id))
                                    .frame(width: blend(144, Self.expandedRowWidth, expansion), alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(height: presentation.rowHeight(row) * row.presence,
                                           alignment: .top)
                                    .opacity(Double(row.presence)).clipped()
                                    .allowsHitTesting(row.presence > 0.95)
                                    .accessibilityHidden(row.presence < 0.5)
                                    .padding(.top, presentation.spacing(before: index))
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
                .buttonStyle(.plain).modifier(ExcludeFromToggle())
                .disabled(presentation.focusedItem?.updates.isEmpty != false)
                .accessibilityLabel(presentation.showsUpdates ? "Hide earlier updates for focused task" : "Show updates for focused task")
                Spacer()
                Text("↑↓  J/K").font(.system(size: 9))
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .frame(height: 30 * expansion * presentation.updatesControlPresence, alignment: .bottom)
            .opacity(Double(expansion * presentation.updatesControlPresence)).clipped()
            .allowsHitTesting(expansion > 0.95 && presentation.updatesControlPresence > 0.95)
            .accessibilityHidden(expansion < 0.5 || presentation.updatesControlPresence < 0.5)
        }
        .padding(.horizontal, Self.horizontalInset(expansion: expansion))
        .padding(.vertical, Self.verticalInset(expansion: expansion))
        .frame(width: blend(200, 350, expansion))
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
            .modifier(ExcludeFromToggle())
            .padding(.horizontal, Self.horizontalInset(expansion: expansion))
            // Keep the X centered on the first compact row despite its larger hit area.
            .padding(.top, Self.verticalInset(expansion: expansion)
                     + (Self.compactRowHeight - 24) / 2 * (1 - expansion))
        }
        .padding(10)
        .coordinateSpace(name: "progressCard")
        .onPreferenceChange(ButtonFramesKey.self) { buttonFrames = $0 }
        .onPreferenceChange(ItemDetailsHeightsKey.self) { heights in
            DispatchQueue.main.async { detailsHeightsChanged(heights) }
        }
        .onPreferenceChange(ItemHistoryHeightsKey.self) { heights in
            DispatchQueue.main.async { historyHeightsChanged(heights) }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(SpatialTapGesture().onEnded { value in
            if !buttonFrames.contains(where: { $0.contains(value.location) }) { toggleCompact() }
        })
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
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(height: 14 * expansion).opacity(Double(expansion)).clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}
