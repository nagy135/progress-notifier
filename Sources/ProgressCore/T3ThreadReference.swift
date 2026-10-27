import Foundation

/// A destination in T3 Code, independent of the task's display name and project.
public struct T3ThreadReference: Codable, Equatable {
    public let environmentId: String
    public let threadId: String

    public init(environmentId: String, threadId: String) {
        self.environmentId = environmentId
        self.threadId = threadId
    }

    public func validated() throws -> T3ThreadReference {
        for (field, value) in [("environmentId", environmentId), ("threadId", threadId)] {
            guard !value.isEmpty, value.count <= 512,
                  value.unicodeScalars.allSatisfy({
                      (65...90).contains($0.value) || (97...122).contains($0.value)
                          || (48...57).contains($0.value) || $0 == "-" || $0 == "_" || $0 == ":"
                  }) else {
                throw APIError(400, "t3Thread.\(field) must contain 1–512 ASCII letters, digits, hyphens, underscores, or colons")
            }
        }
        return self
    }

    public var url: URL? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard (try? validated()) != nil,
              let environment = environmentId.addingPercentEncoding(withAllowedCharacters: allowed),
              let thread = threadId.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        var components = URLComponents()
        components.scheme = "t3code"
        components.host = "threads"
        components.percentEncodedPath = "/\(environment)/\(thread)"
        return components.url
    }
}
