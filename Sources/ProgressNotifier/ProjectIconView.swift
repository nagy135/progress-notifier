import AppKit
import SwiftUI
import ProgressCore

private enum LucideCatalog {
    static let icons: [String: String] = {
        guard let url = Bundle.module.url(forResource: "lucide-icons", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let icons = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return icons
    }()
    static let images = NSCache<NSString, NSImage>()

    static func image(named name: String) -> NSImage? {
        if let cached = images.object(forKey: name as NSString) { return cached }
        guard let svg = icons[name], let image = NSImage(data: Data(svg.utf8)) else { return nil }
        image.isTemplate = true
        images.setObject(image, forKey: name as NSString)
        return image
    }
}

struct ProjectIconView: View {
    let project: String
    let icon: ProjectIcon?
    @Environment(\.colorScheme) private var colorScheme

    private var resolved: ProjectIcon { icon ?? .defaultIcon(for: project) }
    private var tint: Color {
        // Tailwind's 600/400 palette, as used by T3 in light/dark mode.
        let light: [UInt32] = [0x4b5563, 0xdc2626, 0xea580c, 0xd97706, 0xca8a04, 0x65a30d,
            0x16a34a, 0x059669, 0x0d9488, 0x0891b2, 0x0284c7, 0x2563eb, 0x4f46e5, 0x7c3aed,
            0x9333ea, 0xc026d3, 0xdb2777, 0xe11d48]
        let dark: [UInt32] = [0x9ca3af, 0xf87171, 0xfb923c, 0xfbbf24, 0xfacc15, 0xa3e635,
            0x4ade80, 0x34d399, 0x2dd4bf, 0x22d3ee, 0x38bdf8, 0x60a5fa, 0x818cf8, 0xa78bfa,
            0xc084fc, 0xe879f9, 0xf472b6, 0xfb7185]
        let index = ProjectIcon.colors.firstIndex(of: resolved.color ?? "gray") ?? 0
        let hex = (colorScheme == .dark ? dark : light)[index]
        return Color(red: Double((hex >> 16) & 255) / 255,
                     green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }

    var body: some View {
        Group {
            switch resolved.kind {
            case .emoji:
                Text(resolved.emoji ?? "").font(.system(size: 13))
            case .lucide:
                if let image = LucideCatalog.image(named: resolved.name ?? "") {
                    Image(nsImage: image).resizable().scaledToFit().padding(1).foregroundStyle(tint)
                } else {
                    monogram(.defaultIcon(for: project))
                }
            case .monogram:
                monogram(resolved)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }

    private func monogram(_ icon: ProjectIcon) -> some View {
        Text(icon.text ?? "PR")
            .font(.system(size: 8.25, weight: .bold, design: .monospaced))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
    }
}
