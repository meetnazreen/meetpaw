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

    func waitForCallback(timeout: TimeInterval = 120) async throws -> OAuthCallback {
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
            let page = Self.successPage
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

    /// Branded page shown in the browser after the OAuth redirect lands.
    private static let successPage = """
    <!doctype html><html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Signed in · MeetPaw</title>
    <style>
      :root { --accent: oklch(64.6% .222 41.116); }
      * { box-sizing: border-box; }
      html,body { height: 100%; margin: 0; }
      body { display: flex; align-items: center; justify-content: center;
        font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
        color: #1a1a1a; background: #fafafa; text-align: center; padding: 24px; }
      .card { max-width: 380px; }
      .icon { width: 84px; height: 84px; border-radius: 20px; margin: 0 auto 22px;
        display: flex; align-items: center; justify-content: center;
        background: linear-gradient(160deg, oklch(70% .2 45), var(--accent));
        box-shadow: 0 12px 30px -10px color-mix(in oklch, var(--accent), transparent 50%); }
      h1 { font-size: 1.5rem; margin: 0 0 8px; letter-spacing: -.02em; }
      p { color: #666; margin: 0; }
      .hint { margin-top: 18px; font-size: .9rem; color: #aaa; }
    </style></head><body><div class="card">
      <div class="icon">
        <svg width="46" height="46" viewBox="0 0 100 100" fill="#fff" aria-hidden="true">
          <ellipse cx="30" cy="33" rx="8" ry="11"/>
          <ellipse cx="47" cy="25" rx="8.5" ry="12"/>
          <ellipse cx="64" cy="27" rx="8.5" ry="12"/>
          <ellipse cx="78" cy="40" rx="7.5" ry="10.5"/>
          <path d="M34 64 Q34 46 54 46 Q74 46 74 64 Q74 83 54 83 Q34 83 34 64 Z"/>
        </svg>
      </div>
      <h1>You're signed in to MeetPaw</h1>
      <p>You can close this tab and head back to the app in your menu bar.</p>
      <p class="hint">This window will try to close automatically…</p>
    </div>
    <script>setTimeout(function(){ try { window.close(); } catch(e){} }, 800);</script>
    </body></html>
    """

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
