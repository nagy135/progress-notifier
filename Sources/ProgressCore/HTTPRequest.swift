import Foundation

public struct HTTPRequest {
    public let method: String
    public let target: String
    public let headers: [String: String]
    public let body: Data

    /// nil means more bytes are needed. Each connection handles one bounded request.
    public static func parse(_ data: Data) throws -> HTTPRequest? {
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else {
            if data.count > 8192 { throw APIError(431, "Headers too large") }
            return nil
        }
        guard boundary.lowerBound <= 8192 else { throw APIError(431, "Headers too large") }
        guard let text = String(data: data[..<boundary.lowerBound], encoding: .utf8) else {
            throw APIError(400, "Invalid headers")
        }
        let lines = text.components(separatedBy: "\r\n")
        let start = lines[0].split(separator: " ")
        guard start.count == 3, start[2] == "HTTP/1.1" || start[2] == "HTTP/1.0",
              start[1].hasPrefix("/") else { throw APIError(400, "Invalid request line") }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw APIError(400, "Invalid header") }
            let key = line[..<colon].lowercased()
            guard !key.isEmpty, headers[key] == nil else { throw APIError(400, "Duplicate or empty header") }
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil else { throw APIError(400, "Chunked requests are unsupported") }
        let length: Int
        if let raw = headers["content-length"] {
            guard !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let parsed = Int(raw), parsed <= 16384 else { throw APIError(413, "Invalid or oversized Content-Length") }
            length = parsed
        } else {
            guard start[0] != "POST" else { throw APIError(411, "Content-Length required") }
            length = 0
        }
        let bodyStart = boundary.upperBound
        guard data.count - bodyStart >= length else { return nil }
        return HTTPRequest(method: String(start[0]), target: String(start[1]), headers: headers,
                           body: data.subdata(in: bodyStart..<(bodyStart + length)))
    }
}
