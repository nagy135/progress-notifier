import Foundation
import Network
import ProgressCore

struct HTTPResponse {
    let status: Int
    let body: Data
    init(_ status: Int = 200, _ value: Any) {
        self.status = status
        self.body = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
    var data: Data {
        let reason = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found",
                      405: "Method Not Allowed", 408: "Request Timeout", 409: "Conflict",
                      411: "Length Required", 413: "Payload Too Large", 415: "Unsupported Media Type",
                      431: "Request Header Fields Too Large", 500: "Internal Server Error"][status] ?? "Error"
        var data = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".utf8)
        data.append(body)
        return data
    }
}

final class HTTPServer {
    private let queue = DispatchQueue(label: "progress-notifier.http")
    private var listener: NWListener?
    private var sessions: [UUID: HTTPSession] = [:]
    var handle: ((HTTPRequest) -> HTTPResponse)?
    var stateChanged: ((String?) -> Void)?

    func start() throws {
        let parameters = NWParameters.tcp
        // Binding the address (not just an interface or port) keeps this API off the LAN.
        // Apple: https://developer.apple.com/documentation/network/nwparameters/requiredlocalendpoint
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 8766)
        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            if case .ready = state { DispatchQueue.main.async { self?.stateChanged?(nil) } }
            if case .failed(let error) = state {
                listener?.cancel()
                DispatchQueue.main.async { self?.stateChanged?(error.localizedDescription) }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.sessions.count < 64 else { connection.cancel(); return }
            let id = UUID()
            let session = HTTPSession(connection: connection, queue: self.queue)
            self.sessions[id] = session
            session.finished = { [weak self] in self?.sessions.removeValue(forKey: id) }
            session.request = { [weak self, weak session] request in
                DispatchQueue.main.async {
                    let response = self?.handle?(request) ?? HTTPResponse(500, ["error": "Server stopped"])
                    session?.respond(response)
                }
            }
            session.start()
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        queue.async { [self] in
            let current = Array(sessions.values)
            current.forEach { $0.cancel() }
        }
    }
}

private final class HTTPSession {
    let connection: NWConnection
    let queue: DispatchQueue
    var request: ((HTTPRequest) -> Void)?
    var finished: (() -> Void)?
    private var buffer = Data()
    private var timer: DispatchWorkItem?
    private var responding = false
    private var ended = false

    init(connection: NWConnection, queue: DispatchQueue) { self.connection = connection; self.queue = queue }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.cancel()
            default: break
            }
        }
        connection.start(queue: queue)
        let timer = DispatchWorkItem { [weak self] in self?.send(HTTPResponse(408, ["error": "Request timed out"])) }
        self.timer = timer
        queue.asyncAfter(deadline: .now() + 5, execute: timer)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self, !self.ended else { return }
            if let data { self.buffer.append(data) }
            do {
                if let parsed = try HTTPRequest.parse(self.buffer) {
                    self.timer?.cancel()
                    self.request?(parsed)
                } else if complete || error != nil { self.cancel() }
                else { self.receive() }
            } catch let error as APIError { self.send(HTTPResponse(error.status, ["error": error.message])) }
            catch { self.send(HTTPResponse(400, ["error": "Invalid request"])) }
        }
    }

    func respond(_ response: HTTPResponse) { queue.async { [weak self] in self?.send(response) } }

    private func send(_ response: HTTPResponse) {
        guard !ended, !responding else { return }
        responding = true
        timer?.cancel()
        connection.send(content: response.data, completion: .contentProcessed { [weak self] _ in self?.cancel() })
    }

    func cancel() {
        guard !ended else { return }
        ended = true
        timer?.cancel()
        connection.cancel()
        finished?()
        finished = nil
    }
}
