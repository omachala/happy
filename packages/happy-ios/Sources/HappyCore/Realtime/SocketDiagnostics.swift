import Foundation

/// apiSocket.ts `SocketErrorDetails`: the last thing that went wrong with
/// the live socket, kept until the socket connects again or something newer
/// goes wrong, for the connection error screen.
public struct SocketErrorDetails: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        /// Reaching the server failed: the WebSocket, the Engine.IO open,
        /// or the Socket.IO handshake was refused.
        case connectError = "connect_error"
        /// A connected socket went away.
        case disconnect
        /// Anything else the socket threw.
        case error
    }

    /// Milliseconds since 1970.
    public var at: Int64
    public var kind: Kind
    public var message: String
    public var name: String?
    public var description: String?
    public var cause: String?
    /// In the order they are listed (`endpoint`, then `reason`).
    public var extra: [(key: String, value: String)]

    public init(at: Int64, kind: Kind, message: String, name: String? = nil, description: String? = nil, cause: String? = nil, extra: [(key: String, value: String)] = []) {
        self.at = at
        self.kind = kind
        self.message = message
        self.name = name
        self.description = description
        self.cause = cause
        self.extra = extra
    }

    public static func == (lhs: SocketErrorDetails, rhs: SocketErrorDetails) -> Bool {
        lhs.at == rhs.at && lhs.kind == rhs.kind && lhs.message == rhs.message && lhs.name == rhs.name
            && lhs.description == rhs.description && lhs.cause == rhs.cause
            && lhs.extra.map(\.key) == rhs.extra.map(\.key) && lhs.extra.map(\.value) == rhs.extra.map(\.value)
    }

    /// `error` as the screen shows it, from where it happened.
    public init(_ error: Error, kind: Kind, at: Int64, endpoint: String, reason: String? = nil) {
        var extra: [(key: String, value: String)] = [("endpoint", endpoint)]
        if let reason { extra.append(("reason", reason)) }
        let nsError = error as NSError
        var message: String
        var description: String?
        var cause: String?
        switch error {
        case let socket as SocketIOError:
            switch socket {
            case .notConnected: message = "not connected"
            case .protocolViolation(let detail): message = "protocol violation: \(detail)"
            case .connectRejected(let reason): message = reason ?? "connection rejected"
            case .ackTimeout: message = "ack timeout"
            case .closed: message = "closed"
            }
        default:
            message = nsError.localizedDescription
            description = "\(nsError.domain) \(nsError.code)"
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                cause = "\(underlying.domain) \(underlying.code): \(underlying.localizedDescription)"
            }
        }
        if message.isEmpty { message = String(describing: error) }
        self.init(at: at, kind: kind, message: message, name: String(describing: type(of: error)), description: description, cause: cause, extra: extra)
    }
}

/// What the socket last said of itself, read at once from any thread
/// (the connection error screen, the home header).
public final class SocketDiagnostics: @unchecked Sendable {
    public struct Snapshot: Equatable, Sendable {
        public var lastError: SocketErrorDetails?
        /// Milliseconds since 1970.
        public var lastConnectedAt: Int64?
        public var lastDisconnectedAt: Int64?

        public init(lastError: SocketErrorDetails? = nil, lastConnectedAt: Int64? = nil, lastDisconnectedAt: Int64? = nil) {
            self.lastError = lastError
            self.lastConnectedAt = lastConnectedAt
            self.lastDisconnectedAt = lastDisconnectedAt
        }
    }

    private let lock = NSLock()
    private var value = Snapshot()

    public init() {}

    public var snapshot: Snapshot { lock.withLock { value } }

    /// Connected: the error is gone.
    func connected(at: Int64) {
        lock.withLock {
            value.lastConnectedAt = at
            value.lastError = nil
        }
    }

    /// Something went wrong; it stands until the next connect.
    func failed(_ error: SocketErrorDetails, disconnected: Bool) {
        lock.withLock {
            value.lastError = error
            if disconnected { value.lastDisconnectedAt = error.at }
        }
    }

    func disconnected(at: Int64) {
        lock.withLock { value.lastDisconnectedAt = at }
    }
}

/// connection-error.tsx `formatDetails`: the text the screen shows and
/// copies.
public enum ConnectionErrorReport {
    /// `server` is the account's server; `custom` whether it is someone's
    /// own rather than the default.
    public static func format(
        status: RealtimeStatus,
        diagnostics: SocketDiagnostics.Snapshot,
        client: String,
        server: URL,
        custom: Bool,
        now: Date = Date()
    ) -> String {
        func iso(_ ms: Int64?) -> String {
            guard let ms, ms != 0 else { return "never" }
            return isoString(Date(timeIntervalSince1970: Double(ms) / 1000))
        }
        let host = server.host ?? server.absoluteString
        let port = server.port.map { ":\($0)" } ?? ""
        var lines = [
            "# Happy connection error",
            "",
            "captured-at: \(isoString(now))",
            "client: \(client)",
            "server: \(host)\(port) (custom=\(custom))",
            "status: \(name(status))",
            "lastConnectedAt: \(iso(diagnostics.lastConnectedAt))",
            "lastDisconnectedAt: \(iso(diagnostics.lastDisconnectedAt))",
            "",
        ]
        lines.append("## Error")
        if let error = diagnostics.lastError {
            lines.append("kind: \(error.kind.rawValue)")
            lines.append("at: \(iso(error.at))")
            if let name = error.name { lines.append("name: \(name)") }
            lines.append("message: \(error.message)")
            if let description = error.description { lines.append("description: \(description)") }
            if let cause = error.cause { lines.append("cause: \(cause)") }
            if !error.extra.isEmpty {
                lines.append("extra:")
                for (key, value) in error.extra { lines.append("  \(key): \(value)") }
            }
        } else {
            lines.append("(no error details captured)")
        }
        return lines.joined(separator: "\n")
    }

    /// The socket's status in apiSocket.ts's words.
    public static func name(_ status: RealtimeStatus) -> String {
        switch status {
        case .connected: "connected"
        case .connecting: "connecting"
        case .disconnected: "disconnected"
        case .error: "error"
        }
    }

    /// `Date.toISOString()`: UTC with milliseconds.
    static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
