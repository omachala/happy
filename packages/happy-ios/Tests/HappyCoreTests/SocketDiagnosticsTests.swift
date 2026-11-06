import Foundation
import XCTest
@testable import HappyCore
import HappyWire

/// The fork's connection error capture (apiSocket.ts) and its report
/// (connection-error.tsx `formatDetails`).
final class SocketDiagnosticsTests: XCTestCase {
    private let at: Int64 = 1_762_430_400_000 // 2025-11-06T12:00:00.000Z

    func testTheReportWithAnError() {
        let error = SocketErrorDetails(
            at: at, kind: .connectError, message: "Could not connect to the server.", name: "URLError",
            description: "NSURLErrorDomain -1004", cause: "kCFErrorDomainCFNetwork 61: refused",
            extra: [("endpoint", "wss://happy.example/v1/updates/"), ("reason", "transport close")]
        )
        let text = ConnectionErrorReport.format(
            status: .error,
            diagnostics: .init(lastError: error, lastConnectedAt: at - 60_000, lastDisconnectedAt: nil),
            client: "ios/2.0.0",
            server: URL(string: "https://happy.example:8443")!,
            custom: true,
            now: Date(timeIntervalSince1970: Double(at + 1_500) / 1000)
        )
        XCTAssertEqual(text, """
        # Happy connection error

        captured-at: 2025-11-06T12:00:01.500Z
        client: ios/2.0.0
        server: happy.example:8443 (custom=true)
        status: error
        lastConnectedAt: 2025-11-06T11:59:00.000Z
        lastDisconnectedAt: never

        ## Error
        kind: connect_error
        at: 2025-11-06T12:00:00.000Z
        name: URLError
        message: Could not connect to the server.
        description: NSURLErrorDomain -1004
        cause: kCFErrorDomainCFNetwork 61: refused
        extra:
          endpoint: wss://happy.example/v1/updates/
          reason: transport close
        """)
    }

    func testTheReportWithoutAnError() {
        let text = ConnectionErrorReport.format(
            status: .connecting, diagnostics: .init(), client: "ios/2.0.0",
            server: URL(string: "https://api.cluster-fluster.com")!, custom: false,
            now: Date(timeIntervalSince1970: Double(at) / 1000)
        )
        XCTAssertTrue(text.hasSuffix("status: connecting\nlastConnectedAt: never\nlastDisconnectedAt: never\n\n## Error\n(no error details captured)"), text)
        XCTAssertTrue(text.contains("server: api.cluster-fluster.com (custom=false)"))
    }

    func testErrorsAreDescribedFromWhereTheyHappened() {
        let refused = SocketErrorDetails(SocketIOError.connectRejected("Invalid token"), kind: .connectError, at: at, endpoint: "wss://x")
        XCTAssertEqual(refused.message, "Invalid token")
        XCTAssertEqual(refused.name, "SocketIOError")
        XCTAssertEqual(refused.extra.map(\.key), ["endpoint"])

        let dropped = SocketErrorDetails(URLError(.networkConnectionLost), kind: .disconnect, at: at, endpoint: "wss://x", reason: "transport error")
        XCTAssertEqual(dropped.description, "NSURLErrorDomain -1005")
        XCTAssertEqual(dropped.extra.map(\.value), ["wss://x", "transport error"])
    }

    /// A refused handshake is kept as a `connect_error` until the socket
    /// connects again, which clears it.
    func testTheClientCapturesAndClearsErrors() async throws {
        let connector = FakeConnector()
        let client = SocketIOClient(url: URL(string: "wss://x/v1/updates/")!, connector: connector, backoff: Backoff(initial: .milliseconds(1), maximum: .milliseconds(2))) {
            .object(["token": .string("t")])
        }
        await client.connect()
        await eventually { connector.latest != nil }
        let first = try XCTUnwrap(connector.latest)
        first.push(#"0{"sid":"s","upgrades":[],"pingInterval":15000,"pingTimeout":45000}"#)
        first.push(#"44{"message":"Invalid token"}"#)
        await eventually { client.diagnostics.snapshot.lastError != nil }
        let refused = try XCTUnwrap(client.diagnostics.snapshot.lastError)
        XCTAssertEqual(refused.kind, .connectError)
        XCTAssertEqual(refused.message, "Invalid token")
        XCTAssertEqual(refused.extra.first?.value, "wss://x/v1/updates/")
        XCTAssertNil(client.diagnostics.snapshot.lastDisconnectedAt)

        await eventually { connector.sockets.count >= 2 }
        let second = try XCTUnwrap(connector.latest)
        second.push(#"0{"sid":"s","upgrades":[],"pingInterval":15000,"pingTimeout":45000}"#)
        second.push(#"40{"sid":"ns"}"#)
        await eventually { await client.status == .connected }
        XCTAssertNil(client.diagnostics.snapshot.lastError)
        XCTAssertNotNil(client.diagnostics.snapshot.lastConnectedAt)

        // The server drops it: a disconnect, with its reason.
        second.push("41")
        await eventually { client.diagnostics.snapshot.lastError?.kind == .disconnect }
        XCTAssertEqual(client.diagnostics.snapshot.lastError?.extra.last?.value, "transport close")
        XCTAssertNotNil(client.diagnostics.snapshot.lastDisconnectedAt)
        await client.disconnect()
    }
}
