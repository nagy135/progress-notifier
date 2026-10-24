import Foundation

/// Uses the same icon descriptors and default monogram algorithm as T3 projects.
public struct ProjectIcon: Codable, Equatable {
    public enum Kind: String, Codable { case emoji, lucide, monogram }
    public let kind: Kind
    public let name: String?
    public let color: String?
    public let emoji: String?
    public let text: String?

    public static let colors = ["gray", "red", "orange", "amber", "yellow", "lime", "green", "emerald",
                                "teal", "cyan", "sky", "blue", "indigo", "violet", "purple", "fuchsia", "pink", "rose"]

    public init(kind: Kind, name: String? = nil, color: String? = nil, emoji: String? = nil, text: String? = nil) {
        self.kind = kind
        self.name = name
        self.color = color
        self.emoji = emoji
        self.text = text
    }

    public func validated() throws -> ProjectIcon {
        func validText(_ value: String?, limit: Int) -> Bool {
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= limit
                && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        }
        switch kind {
        case .emoji:
            guard validText(emoji, limit: 16) else { throw APIError(400, "projectIcon.emoji must contain 1–16 characters") }
        case .monogram:
            guard validText(text, limit: 2), Self.colors.contains(color ?? "") else {
                throw APIError(400, "projectIcon requires 1–2 monogram characters and a T3 color")
            }
        case .lucide:
            guard validText(name, limit: 64),
                  name?.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil,
                  Self.colors.contains(color ?? "") else {
                throw APIError(400, "projectIcon requires a kebab-case Lucide name and a T3 color")
            }
        }
        return self
    }

    public static func defaultIcon(for project: String) -> ProjectIcon {
        let normalized = project.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        var monogram = "PR"
        if let first = words.first, let initial = first.first {
            let second = first.dropFirst().first(where: { $0.isNumber })
                ?? (words.count > 1 ? words.last?.first : first.last) ?? initial
            monogram = String("\(initial)\(second)".uppercased().prefix(2))
        }
        let seed = normalized.isEmpty ? "project" : normalized.lowercased(with: Locale(identifier: "en_US"))
        let index = seed.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % colors.count }
        return ProjectIcon(kind: .monogram, color: colors[index], text: monogram)
    }
}
