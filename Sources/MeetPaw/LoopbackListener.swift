import Foundation
import Network

struct OAuthCallback {
    let code: String?
    let state: String?
    let error: String?
}

/// Tiny HTTP listener on 127.0.0.1:<random port> that captures the single
/// OAuth redirect, replies with a close-me page, then shuts down.
final class LoopbackListener {
    private let listener: NWListener
    private var continuation: CheckedContinuation<OAuthCallback, Error>?

    init() throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        listener = try NWListener(using: params, on: .any)
    }

    /// Starts listening and resolves with the chosen port.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { cont in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = self.listener.port?.rawValue { cont.resume(returning: port) }
                case .failed(let err):
                    cont.resume(throwing: err)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            listener.start(queue: .global())
        }
    }

    func waitForCallback() async throws -> OAuthCallback {
        try await withCheckedThrowingContinuation { cont in self.continuation = cont }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global())
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                conn.cancel(); return
            }
            let callback = self.parse(request)
            let page = "You can close this tab and return to MeetPaw. 🐾"
            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(page.utf8.count)\r
            Connection: close\r
            \r
            \(page)
            """
            conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                conn.cancel()
                self.listener.cancel()
            })
            self.continuation?.resume(returning: callback)
            self.continuation = nil
        }
    }

    private func parse(_ request: String) -> OAuthCallback {
        // First line: "GET /?code=...&state=... HTTP/1.1"
        guard let line = request.split(separator: "\r\n").first,
              let path = line.split(separator: " ").dropFirst().first,
              let comps = URLComponents(string: "http://127.0.0.1\(path)") else {
            return OAuthCallback(code: nil, state: nil, error: "Could not parse redirect.")
        }
        let items = comps.queryItems ?? []
        func value(_ n: String) -> String? { items.first { $0.name == n }?.value }
        return OAuthCallback(code: value("code"), state: value("state"), error: value("error"))
    }
}
