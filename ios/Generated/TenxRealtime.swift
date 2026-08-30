import Foundation

/// Authenticated realtime (WebSocket) client for a Paid Backend
/// `@router.websocket` route. 10x proxies the socket bidirectionally through
/// the project API WebSocket URL.
///
/// The crux: a managed access token lives only ~1 hour, so a socket opened
/// once with a snapshot token is silently dropped by the proxy at expiry and
/// never comes back ("connection lost after ~1h"). `TenxRealtime` solves this
/// by (1) fetching a FRESH token from `TenxSession` at every connect, and
/// (2) automatically reconnecting — with a newly refreshed token — whenever
/// the socket drops or the token expires, using bounded exponential backoff.
/// Consume `messages` as an async stream and `send(_:)` to publish; the stream
/// stays live across reconnects. It ends without error on `close()`, or throws
/// if the endpoint can never be reached (e.g. a Paid-only route) — catch that
/// to show a real error, then call `connect()` again to retry.
///
/// Usage:
/// ```
/// let socket = TenxRealtime(path: "/api/v1/match-socket")
/// await socket.connect()
/// Task {
///     for try await message in await socket.messages {
///         if case let .string(text) = message { handle(text) }
///     }
/// }
/// try await socket.send(.string(#"{"type":"move","column":3}"#))
/// ```
public actor TenxRealtime {
    public enum Message: Sendable, Equatable {
        case string(String)
        case data(Data)
    }

    public enum State: Sendable, Equatable {
        case idle
        case connecting
        case connected
        case reconnecting
        case closed
        /// The socket never established a live connection across all initial
        /// attempts (e.g. the route needs a Paid backend, does not exist, or
        /// the token was rejected). The `messages` stream throws the real
        /// error; call `connect()` again to retry.
        case failed
    }

    private let path: String
    private let session: URLSession
    private let tokenProvider: @Sendable () async throws -> String
    private let queryItems: [URLQueryItem]

    // Bounded exponential backoff between reconnect attempts.
    private let baseBackoff: TimeInterval = 0.5
    private let maxBackoff: TimeInterval = 30
    // How many initial connect attempts (before any frame is ever received)
    // may fail before the socket is declared permanently unreachable instead
    // of retrying behind a silent spinner. Chosen so the retry window spans
    // ~roughly a minute — long enough to ride out a cold backend start, short
    // enough that a genuinely rejected route surfaces its error promptly.
    private let maxInitialConnectAttempts = 8

    private var task: URLSessionWebSocketTask?
    private var runLoop: Task<Void, Never>?
    private var continuation: AsyncThrowingStream<Message, Error>.Continuation?
    private var stream: AsyncThrowingStream<Message, Error>?
    private var reconnectAttempt = 0
    // Flips true the first time ANY frame is received on ANY connection, and
    // never resets for the life of the socket. Once true, every later drop
    // reconnects forever (transient); until true, exhausting the initial
    // attempts means the endpoint is rejecting us, not transiently down.
    private var hasEverConnected = false
    private var isClosed = false
    // Frames enqueued via send() before the socket finished opening. connect()
    // launches the loop and returns before task is set, so the documented
    // `connect(); send(...)` sequence would otherwise throw; buffer instead and
    // flush on connect. Bounded so a never-connecting socket can't grow it.
    private var pendingSends: [Message] = []
    private let maxPendingSends = 64
    public private(set) var state: State = .idle

    /// - Parameters:
    ///   - path: the declared backend route, e.g. `/api/v1/match-socket`.
    ///   - queryItems: optional query parameters appended to the socket URL.
    ///   - session: the URLSession to open the socket on.
    ///   - tokenProvider: supplies a FRESH access token for each connect. The
    ///     default pulls from `TenxSession.shared`, which transparently
    ///     refreshes the ~60-minute token — this is what lets the socket
    ///     survive past token expiry via reconnect.
    public init(
        path: String,
        queryItems: [URLQueryItem] = [],
        session: URLSession = .shared,
        tokenProvider: @escaping @Sendable () async throws -> String = { try await TenxSession.shared.validAccessToken() }
    ) {
        self.path = path
        self.queryItems = queryItems
        self.session = session
        self.tokenProvider = tokenProvider
    }

    /// The live message stream. Survives reconnects. It finishes without error
    /// when you call `close()`, and finishes by THROWING the underlying error
    /// if the socket can never establish a connection (state becomes `.failed`
    /// — e.g. the route needs a Paid backend or does not exist). To retry after
    /// a `.failed`, call `connect()` again and re-read `messages` for a fresh
    /// stream. Iterate it once.
    public var messages: AsyncThrowingStream<Message, Error> {
        if let stream {
            return stream
        }
        let created = AsyncThrowingStream<Message, Error> { continuation in
            self.continuation = continuation
        }
        stream = created
        return created
    }

    /// Open the socket and start the receive + auto-reconnect loop. Safe to
    /// call once; subsequent calls are ignored while a loop is running.
    public func connect() {
        guard runLoop == nil, !isClosed else { return }
        _ = messages // ensure the stream/continuation exist before the loop runs
        runLoop = Task { [weak self] in
            await self?.runConnectionLoop()
        }
    }

    /// Send a text or binary frame. If the socket is still opening (e.g. you
    /// called `connect()` then immediately `send(...)`), the frame is buffered
    /// and flushed once connected, in order. Throws only if the socket is
    /// closed, has permanently failed, or was never connected.
    public func send(_ message: Message) async throws {
        if isClosed || state == .failed {
            throw TenxBackendError.invalidResponse
        }
        if let task {
            try await rawSend(on: task, message)
            return
        }
        // The socket is mid-connect (connect() launched the loop but task is
        // not set yet). Buffer and let the connect flush it, rather than
        // throwing on a benign connect()/send() race.
        guard runLoop != nil else {
            throw TenxBackendError.invalidResponse
        }
        if pendingSends.count >= maxPendingSends {
            pendingSends.removeFirst()
        }
        pendingSends.append(message)
    }

    private func rawSend(on task: URLSessionWebSocketTask, _ message: Message) async throws {
        switch message {
        case .string(let text):
            try await task.send(.string(text))
        case .data(let data):
            try await task.send(.data(data))
        }
    }

    /// Flush buffered frames on a freshly connected socket, in order. On the
    /// first send error the remainder stays buffered for the next connect.
    private func flushPendingSends(on socket: URLSessionWebSocketTask) async {
        while !pendingSends.isEmpty, !isClosed, !Task.isCancelled {
            let message = pendingSends[0]
            do {
                try await rawSend(on: socket, message)
                if !pendingSends.isEmpty { pendingSends.removeFirst() }
            } catch {
                return
            }
        }
    }

    public func send(_ text: String) async throws {
        try await send(.string(text))
    }

    /// Permanently close the socket and finish the message stream. After this
    /// the client will not reconnect.
    public func close() {
        isClosed = true
        state = .closed
        runLoop?.cancel()
        runLoop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        pendingSends.removeAll()
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Connection loop

    private func runConnectionLoop() async {
        while !isClosed, !Task.isCancelled {
            var loopError: Error?
            do {
                let token = try await tokenProvider()
                let socket = try makeTask(token: token)
                task = socket
                state = reconnectAttempt == 0 ? .connecting : .reconnecting
                socket.resume()
                state = .connected
                // Flush any frames buffered while the socket was opening.
                await flushPendingSends(on: socket)
                // Do NOT reset reconnectAttempt here: resume() does not await the
                // handshake, so a rejected upgrade (unpaid gate, bad route, bad
                // token) throws immediately in receiveLoop. Resetting the backoff
                // before the connection is proven live pins it at attempt 0 and
                // hammers the proxy ~2-4x/sec forever. The reset happens after the
                // first real frame arrives (see receiveLoop).
                // Pump frames until the socket drops; a thrown error breaks out
                // to the reconnect path below.
                try await receiveLoop(on: socket)
            } catch {
                if isClosed || Task.isCancelled { break }
                // Remember the error so that, if the socket never once connects,
                // it can be surfaced to the caller instead of silently retried.
                loopError = error
            }
            task?.cancel(with: .goingAway, reason: nil)
            task = nil
            if isClosed || Task.isCancelled { break }
            // A socket that has NEVER delivered a frame across all initial
            // attempts is being rejected (Paid-only route, missing route, bad
            // token), not transiently dropped. Surface the real error on the
            // stream so the app can stop showing an endless spinner. This is
            // NOT a permanent close: reset so a later connect() retries cleanly
            // (e.g. after an upgrade or on a user "retry" tap).
            if !hasEverConnected, reconnectAttempt >= maxInitialConnectAttempts {
                state = .failed
                continuation?.finish(throwing: loopError ?? TenxBackendError.invalidResponse)
                continuation = nil
                stream = nil
                pendingSends.removeAll()
                reconnectAttempt = 0
                runLoop = nil
                return
            }
            await backoffBeforeReconnect()
        }
        if isClosed {
            continuation?.finish()
            continuation = nil
        }
    }

    private func receiveLoop(on socket: URLSessionWebSocketTask) async throws {
        var proven = false
        while !isClosed, !Task.isCancelled {
            let message = try await socket.receive()
            if !proven {
                // First frame received => the handshake genuinely succeeded, so
                // the exponential backoff can safely reset. On a failing endpoint
                // this line is never reached, so the backoff keeps escalating.
                proven = true
                hasEverConnected = true
                reconnectAttempt = 0
            }
            switch message {
            case .string(let text):
                continuation?.yield(.string(text))
            case .data(let data):
                continuation?.yield(.data(data))
            @unknown default:
                break
            }
        }
    }

    private func backoffBeforeReconnect() async {
        // There is no total-duration ceiling by design: a socket that NEVER
        // connected is already terminated (see the .failed path above), so this
        // path only runs for a socket that connected at least once and then
        // dropped — which should keep retrying indefinitely (the server may
        // return) at the capped max interval. The retry stops on close(). The
        // per-attempt cost is bounded by maxBackoff.
        state = .reconnecting
        let delay = min(maxBackoff, baseBackoff * pow(2, Double(reconnectAttempt)))
        reconnectAttempt += 1
        // Full jitter to avoid a reconnect thundering herd.
        let jittered = Double.random(in: 0...delay)
        try? await Task.sleep(nanoseconds: UInt64(jittered * 1_000_000_000))
    }

    private func makeTask(token: String) throws -> URLSessionWebSocketTask {
        var request = URLRequest(url: try socketURL())
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return session.webSocketTask(with: request)
    }

    /// Build the `ws`/`wss` URL from the project API base URL, joining the
    /// declared backend path the same way `BackendClient` joins REST paths.
    private func socketURL() throws -> URL {
        guard var components = URLComponents(url: TenxProject.projectAPIURL, resolvingAgainstBaseURL: false) else {
            throw TenxBackendError.invalidResponse
        }
        switch components.scheme?.lowercased() {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        case "wss", "ws": break
        default: components.scheme = "wss"
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let requestPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let joined = [basePath, requestPath].filter { !$0.isEmpty }.joined(separator: "/")
        components.path = "/" + joined
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw TenxBackendError.invalidResponse
        }
        return url
    }
}