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

private struct ItemProgressBar: View {
    let item: ProgressItem

    private var tint: Color { item.completing ? .green : Color(red: 0.23, green: 0.72, blue: 0.64) }

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(tint.opacity(0.13))
                .overlay(alignment: .leading) {
                    Capsule().fill(tint).frame(width: proxy.size.width * item.progress / 100)
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
    var scale: CGFloat = 1.035
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var pulseGeneration: UInt64 = 0

    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).fill(tint.opacity(pulse ? 0.18 : 0)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(tint.opacity(pulse ? 0.6 : 0)))
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

/// Shared by the window and its contents so every part follows the same resize.
final class ProgressPresentation: ObservableObject {
    @Published var expansion: CGFloat

    init(compact: Bool) { expansion = compact ? 0 : 1 }
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

private struct ItemCard: View {
    let item: ProgressItem
    let revision: UInt64
    let consumeUpdatePulse: () -> Bool
    let now: Date
    let expansion: CGFloat
    let dismiss: () -> Void
    @State private var detailsHeight: CGFloat = 64

    private var tint: Color { item.completing ? .green : Color(red: 0.23, green: 0.72, blue: 0.64) }
    private var detailOpacity: Double { Double(max(0, (expansion - 0.25) / 0.75)) }
    private var timing: String {
        let estimate = item.completing ? "Complete" : remaining(item.expectedFinish.timeIntervalSince(now))
        return "\(estimate) · \(added(item.createdAt, now: now))"
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let project = item.project {
                Text(project).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary).lineLimit(1).help(project)
                    .frame(height: 16).padding(.leading, 22)
            }
            Text(item.name).font(.system(size: 13, weight: .semibold))
                .lineLimit(2).help(item.name)
            Text(timing)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
                .help(timing)
        }
        .padding(.leading, item.project == nil ? 22 : 0)
        .padding(.trailing, 30)
        // Measure at expanded width even while collapsed: text never rewraps mid-resize.
        .frame(width: 290, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ItemDetailsHeightsKey.self, value: [item.id: proxy.size.height])
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * expansion) {
            details
                .frame(width: 0, height: detailsHeight * expansion, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(detailOpacity).clipped()
                .accessibilityHidden(expansion < 0.5)
            HStack(spacing: 0) {
                Color.clear.frame(width: 22 * (1 - expansion), height: 1)
                ItemProgressBar(item: item)
                Text("\(item.progress, specifier: "%.0f")%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit().foregroundStyle(tint)
                    .frame(width: 38 * expansion, alignment: .trailing)
                    .padding(.leading, 8 * expansion)
                    .opacity(detailOpacity).clipped()
                    .accessibilityHidden(expansion < 0.5)
            }
            .frame(height: blend(24, 16, expansion))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12 * expansion)
        .padding(.vertical, 9 * expansion)
        .overlay(alignment: .topLeading) {
            ProjectIconView(project: item.project ?? item.name, icon: item.projectIcon)
                .padding(.leading, 12 * expansion)
                .padding(.top, blend(4, 9, expansion))
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary).frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Dismiss \(item.name)")
            .accessibilityLabel("Dismiss \(item.name)")
            .modifier(ExcludeFromToggle())
            .padding(.trailing, 12 * expansion).padding(.top, 9 * expansion)
            .opacity(detailOpacity).allowsHitTesting(expansion > 0.95)
            .accessibilityHidden(expansion < 0.5)
        }
        .background(.primary.opacity(0.035 * expansion), in: RoundedRectangle(cornerRadius: 12))
        .modifier(UpdatePulse(revision: revision, consumeUpdatePulse: consumeUpdatePulse,
                              tint: tint, cornerRadius: blend(4, 12, expansion),
                              scale: 1 + 0.035 * expansion))
        .help(item.name)
        .onPreferenceChange(ItemDetailsHeightsKey.self) { heights in
            if let height = heights[item.id], abs(detailsHeight - height) > 0.5 { detailsHeight = height }
        }
    }
}

struct ProgressCard: View {
    static let transitionDuration: TimeInterval = 0.16
    static let expandedChromeHeight: CGFloat = 80

    @ObservedObject var model: ProgressModel
    @ObservedObject var presentation: ProgressPresentation
    let maximumHeight: CGFloat
    let expandedContentHeight: CGFloat?
    let contentHeightChanged: (CGFloat) -> Void
    let toggleCompact: () -> Void
    let close: () -> Void
    @State private var buttonFrames: [CGRect] = []

    private var expansion: CGFloat { presentation.expansion }
    private var runningCount: Int { model.items.filter { !$0.completing }.count }

    static func contentInset(expansion: CGFloat) -> CGFloat { blend(6, 14, expansion) }

    static func compactContentHeight(itemCount: Int) -> CGFloat {
        max(24, CGFloat(itemCount) * 28 - 4)
    }

    static func contentHeight(itemCount: Int, expandedContentHeight: CGFloat?,
                              maximumHeight: CGFloat, expansion: CGFloat) -> CGFloat {
        let expanded = itemCount == 0 ? 100 : expandedContentHeight ?? CGFloat(itemCount) * 100 + 8
        return blend(min(compactContentHeight(itemCount: itemCount), maximumHeight - 32),
                     min(expanded, maximumHeight - expandedChromeHeight), expansion)
    }

    static func windowHeight(itemCount: Int, expandedContentHeight: CGFloat?,
                             maximumHeight: CGFloat, expansion: CGFloat) -> CGFloat {
        20 + 2 * contentInset(expansion: expansion) + 32 * expansion
            + contentHeight(itemCount: itemCount, expandedContentHeight: expandedContentHeight,
                            maximumHeight: maximumHeight, expansion: expansion)
    }

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

            Group {
                if model.displayItems.isEmpty {
                    VStack(spacing: 8 * expansion) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: blend(16, 26, expansion), weight: .light))
                            .foregroundStyle(.mint)
                        Text("No progress").font(.system(size: 14, weight: .medium))
                            .frame(height: 17 * expansion).opacity(Double(expansion)).clipped()
                        Text(model.hasHistory ? "Press H to recall a completed result" : "Waiting for tasks…")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(height: 14 * expansion).opacity(Double(expansion)).clipped()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            VStack(spacing: blend(4, 6, expansion)) {
                                ForEach(model.displayItems) { item in
                                    ItemCard(item: item, revision: model.revision(for: item),
                                             consumeUpdatePulse: { model.consumeUpdatePulse(for: item) },
                                             now: context.date, expansion: expansion) { model.dismiss(item) }
                                        .transition(.opacity)
                                }
                            }
                            .padding(4 * expansion)
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.trailing, 32 * (1 - expansion))
            .frame(height: Self.contentHeight(itemCount: model.displayItems.count,
                                             expandedContentHeight: expandedContentHeight,
                                             maximumHeight: maximumHeight, expansion: expansion))
        }
        .padding(Self.contentInset(expansion: expansion))
        .frame(width: blend(200, 350, expansion))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).fill(Color.mint.opacity(model.isFocused ? 0.06 : 0))
            .allowsHitTesting(false))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .strokeBorder(model.isFocused ? Color.mint.opacity(0.9) : .primary.opacity(0.08),
                          lineWidth: model.isFocused ? 2 : 1))
        // A single, fixed-size control stays anchored to the same corner in both modes.
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary).frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close progress window")
            .accessibilityLabel("Close progress window")
            .modifier(ExcludeFromToggle())
            .padding(Self.contentInset(expansion: expansion))
        }
        .padding(10)
        .coordinateSpace(name: "progressCard")
        .onPreferenceChange(ButtonFramesKey.self) { buttonFrames = $0 }
        .onPreferenceChange(ItemDetailsHeightsKey.self) { heights in
            let items = model.displayItems
            guard !items.isEmpty, items.allSatisfy({ heights[$0.id] != nil }) else { return }
            let height = items.reduce(CGFloat(8)) { $0 + (heights[$1.id] ?? 0) + 42 }
                + CGFloat(max(0, items.count - 1)) * 6
            DispatchQueue.main.async { contentHeightChanged(height) }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(SpatialTapGesture().onEnded { value in
            if !buttonFrames.contains(where: { $0.contains(value.location) }) { toggleCompact() }
        })
    }
}
