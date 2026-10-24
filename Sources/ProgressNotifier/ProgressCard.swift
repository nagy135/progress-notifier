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
            .onAppear { if revision > 0 { flash() } }
            .onChange(of: revision) { _ in flash() }
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

private struct ItemCard: View {
    let item: ProgressItem
    let revision: UInt64
    let now: Date
    let dismiss: () -> Void
    private var tint: Color { item.completing ? .green : Color(red: 0.23, green: 0.72, blue: 0.64) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if item.project == nil {
                    Image(systemName: item.completing ? "checkmark" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 24, height: 24)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let project = item.project {
                        HStack(spacing: 5) {
                            ProjectIconView(project: project, icon: item.projectIcon)
                            Text(project).font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary).lineLimit(1).help(project)
                        }
                    }
                    Text(item.name).font(.system(size: 13, weight: .semibold))
                        .lineLimit(2).help(item.name)
                    Text(item.completing ? "Complete" : remaining(item.expectedFinish.timeIntervalSince(now)))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary).frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Dismiss \(item.name)")
                .accessibilityLabel("Dismiss \(item.name)")
                .modifier(ExcludeFromToggle())
            }
            HStack(spacing: 8) {
                ItemProgressBar(item: item)
                Text("\(item.progress, specifier: "%.0f")%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit().foregroundStyle(tint).frame(width: 38, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .modifier(UpdatePulse(revision: revision, tint: tint, cornerRadius: 12))
    }
}

struct ProgressCard: View {
    static let expandedChromeHeight: CGFloat = 72

    @ObservedObject var model: ProgressModel
    let maximumHeight: CGFloat
    let compact: Bool
    let expandedContentHeight: CGFloat?
    let contentHeightChanged: (CGFloat) -> Void
    let toggleCompact: () -> Void
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var compactPulse = false
    @State private var buttonFrames: [CGRect] = []

    private var runningCount: Int { model.items.filter { !$0.completing }.count }

    static func compactHeight(itemCount: Int, maximumHeight: CGFloat) -> CGFloat {
        guard itemCount > 0 else { return 56 }
        return min(64 + CGFloat(itemCount) * 11 - 6, maximumHeight)
    }

    private func reportContentHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        DispatchQueue.main.async { contentHeightChanged(height) }
    }

    private var controls: some View {
        HStack(spacing: compact ? 2 : 4) {
            Button(action: toggleCompact) {
                Image(systemName: compact ? "arrow.up.left.and.arrow.down.right" : "minus")
                    .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
            }
            .help(compact ? "Expand progress" : "Minimize progress")
            .accessibilityLabel(compact ? "Expand progress" : "Minimize progress")
            .modifier(ExcludeFromToggle())
            Button(action: close) {
                Image(systemName: "xmark").frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
            }
            .help("Close window (Q). Reopen the app to show it again.")
            .accessibilityLabel("Close progress window")
            .modifier(ExcludeFromToggle())
        }
        .font(.system(size: compact ? 10 : 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if compact {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill").font(.system(size: 12)).foregroundStyle(.mint)
                    Text("\(runningCount) \(runningCount == 1 ? "task" : "tasks") running")
                        .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    Spacer(minLength: 0)
                    controls
                }
                .frame(height: 20)
                if !model.items.isEmpty {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(model.items) { item in
                                ItemProgressBar(item: item)
                                    .modifier(UpdatePulse(revision: model.revision(for: item),
                                                          tint: item.completing ? .green : .mint,
                                                          cornerRadius: 2.5, scale: 1))
                            }
                        }
                    }
                    .frame(height: Self.compactHeight(itemCount: model.items.count, maximumHeight: maximumHeight) - 64)
                    .scrollIndicators(.hidden)
                }
            } else {
            HStack {
                Text("Progress").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("\(runningCount) active")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.primary.opacity(0.05), in: Capsule())
                controls
            }.padding(.horizontal, 4)
            if model.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.system(size: 26, weight: .light))
                        .foregroundStyle(.mint)
                    Text("No progress").font(.system(size: 14, weight: .medium))
                    Text("Waiting for tasks…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).frame(height: 100)
            } else {
            ScrollView {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 6) {
                        ForEach(model.items) { item in
                            ItemCard(item: item, revision: model.revision(for: item), now: context.date) { model.dismiss(item.name) }
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }.padding(4)
                }
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { reportContentHeight(proxy.size.height) }
                        .onChange(of: proxy.size.height) { reportContentHeight($0) }
                })
            }
            .frame(height: min(expandedContentHeight ?? CGFloat(model.items.count) * 100 + 8,
                               maximumHeight - Self.expandedChromeHeight))
            .scrollIndicators(.hidden)
            }
            }
        }
        .padding(10)
        .frame(width: compact ? 200 : 350)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 20).fill(.green.opacity(compactPulse ? 0.22 : 0)))
        .scaleEffect(compactPulse && !reduceMotion ? 1.035 : 1)
        .help("Click or press M to toggle size. Q closes the window.")
        .onChange(of: model.items.filter { $0.completing }.count) { count in
            guard compact, count > 0 else { return }
            withAnimation(.easeOut(duration: 0.18)) { compactPulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.4)) { compactPulse = false }
            }
        }
        .padding(compact ? 8 : 10)
        .coordinateSpace(name: "progressCard")
        .onPreferenceChange(ButtonFramesKey.self) { buttonFrames = $0 }
        .contentShape(Rectangle())
        .simultaneousGesture(SpatialTapGesture().onEnded { value in
            if !buttonFrames.contains(where: { $0.contains(value.location) }) { toggleCompact() }
        })
    }
}
