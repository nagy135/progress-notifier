import SwiftUI
import ProgressCore

private func remaining(_ seconds: TimeInterval) -> String {
    if seconds <= 0 { return "Finishing soon" }
    let value = Int(ceil(seconds))
    if value < 60 { return "About \(value)s left" }
    if value < 3600 { return "About \(Int(ceil(seconds / 60)))m left" }
    if value < 86400 { return "About \(value / 3600)h \((value % 3600) / 60)m left" }
    return "About \(value / 86400)d \((value % 86400) / 3600)h left"
}

private struct ItemCard: View {
    let item: ProgressItem
    let now: Date
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    private var tint: Color { item.completing ? .green : Color(red: 0.23, green: 0.72, blue: 0.64) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.completing ? "checkmark" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
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
            }
            HStack(spacing: 12) {
                GeometryReader { proxy in
                    Capsule().fill(tint.opacity(0.13))
                        .overlay(alignment: .leading) {
                            Capsule().fill(tint).frame(width: proxy.size.width * item.progress / 100)
                        }
                }.frame(height: 5)
                Text("\(item.progress, specifier: "%.0f")%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit().foregroundStyle(tint).frame(width: 42, alignment: .trailing)
            }
        }
        .padding(14)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).fill(Color.green.opacity(pulse ? 0.22 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(pulse ? 0.6 : 0)))
        .scaleEffect(pulse && !reduceMotion ? 1.035 : 1)
        .onChange(of: item.completing) { complete in
            guard complete else { return }
            withAnimation(.easeOut(duration: 0.18)) { pulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.4)) { pulse = false }
            }
        }
    }
}

struct ProgressCard: View {
    @ObservedObject var model: ProgressModel
    let maximumHeight: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Progress").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("\(model.items.count) active")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.primary.opacity(0.05), in: Capsule())
            }.padding(.horizontal, 4)
            ScrollView {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 10) {
                        ForEach(model.items) { item in
                            ItemCard(item: item, now: context.date) { model.dismiss(item.name) }
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }.padding(6)
                }
            }
            .frame(height: min(CGFloat(model.items.count) * 116 + 2, maximumHeight - 82))
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .frame(width: 350)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.08)))
        .padding(10)
    }
}
