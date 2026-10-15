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

    init(port: Int? = nil) throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        if let port, let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) {
            listener = try NWListener(using: params, on: nwPort)
        } else {
            listener = try NWListener(using: params, on: .any)
        }
    }

    deinit { listener.cancel() }

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

    func waitForCallback(timeout: TimeInterval = 300) async throws -> OAuthCallback {
        try await withThrowingTaskGroup(of: OAuthCallback.self) { group in
            group.addTask { try await self.awaitRedirect() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw AuthError.server("Sign-in timed out.")
            }
            defer { group.cancelAll(); self.listener.cancel() }
            return try await group.next()!
        }
    }

    private func awaitRedirect() async throws -> OAuthCallback {
        try await withCheckedThrowingContinuation { cont in self.continuation = cont }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global())
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                conn.cancel(); return
            }
            let callback = self.parse(request)
            // The code is already captured; send the browser to our branded page
            // on meetpaw.app so the user lands on our domain with the real logo.
            let response = """
            HTTP/1.1 302 Found\r
            Location: https://meetpaw.app/signed-in/\r
            Content-Length: 0\r
            Connection: close\r
            \r
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
