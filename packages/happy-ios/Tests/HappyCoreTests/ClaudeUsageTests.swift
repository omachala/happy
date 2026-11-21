import Foundation
import XCTest
@testable import HappyCore
import HappyWire

/// The fork's Claude usage pill (useClaudeUsage.ts, UsagePill.tsx): what is
/// asked, how the answer reads, and the words for every failure.
final class ClaudeUsageTests: XCTestCase {
    private let body = #"""
    {"five_hour":{"utilization":42.4,"resets_at":"2026-11-06T15:30:00.123456+00:00"},
     "seven_day":{"utilization":81,"resets_at":null},
     "extra_usage":{"is_enabled":true,"utilization":50,"used_credits":1234,"monthly_limit":5000}}
    """#

    func testTheAnswerIsReadAsTheForkReadsIt() throws {
        let usage = ClaudeUsage(json: try JSONValue.decode(Data(body.utf8)))
        XCTAssertEqual(usage.fiveHour, .init(utilization: 42.4, resetsAt: "2026-11-06T15:30:00.123456+00:00"))
        XCTAssertEqual(usage.sevenDay, .init(utilization: 81, resetsAt: nil))
        XCTAssertEqual(usage.extra, .init(utilization: 50, usedCents: 1234, limitCents: 5000))

        let sparse = ClaudeUsage(json: try JSONValue.decode(Data(#"{"extra_usage":{"is_enabled":false,"utilization":9}}"#.utf8)))
        XCTAssertEqual(sparse, ClaudeUsage(fiveHour: .init(utilization: 0, resetsAt: nil), sevenDay: nil, extra: nil))
    }

    /// The weekly window shows beside the session's when the answer has it,
    /// and is left out (never a made-up 0%) when it is null or missing, as
    /// from an older server or a plan without a weekly cap.
    func testTheWeeklyFigure() throws {
        func read(_ text: String) throws -> ClaudeUsage { ClaudeUsage(json: try JSONValue.decode(Data(text.utf8))) }
        let both = try read(#"{"five_hour":{"utilization":26},"seven_day":{"utilization":"41.2","resets_at":"2026-11-23T08:00:00+00:00"}}"#)
        XCTAssertEqual(both.sevenDay, .init(utilization: 41.2, resetsAt: "2026-11-23T08:00:00+00:00"))
        XCTAssertEqual(ClaudeUsageFormat.percent(both.sevenDay?.utilization ?? 0), "41%")

        for missing in [#"{"five_hour":{"utilization":26}}"#, #"{"five_hour":{"utilization":26},"seven_day":null}"#, #"{"five_hour":{"utilization":26},"seven_day":{"utilization":null}}"#] {
            let usage = try read(missing)
            XCTAssertNil(usage.sevenDay, missing)
        }
    }

    func testPercentagesAndBuckets() {
        XCTAssertEqual(ClaudeUsageFormat.percent(42.4), "42%")
        XCTAssertEqual(ClaudeUsageFormat.percent(42.5), "43%", "Math.round")
        XCTAssertEqual(ClaudeUsageFormat.percent(0), "0%")
        XCTAssertEqual(ClaudeUsageFormat.level(49.9), .low)
        XCTAssertEqual(ClaudeUsageFormat.level(50), .medium)
        XCTAssertEqual(ClaudeUsageFormat.level(79.9), .medium)
        XCTAssertEqual(ClaudeUsageFormat.level(80), .high)
        XCTAssertEqual(ClaudeUsageFormat.fraction(-5), 0)
        XCTAssertEqual(ClaudeUsageFormat.fraction(42), 0.42)
        XCTAssertEqual(ClaudeUsageFormat.fraction(140), 1)
        XCTAssertEqual(ClaudeUsageFormat.extraSpend(.init(utilization: 0, usedCents: 1234, limitCents: 5000)), "$12.34 / $50.00")
    }

    func testWeeklyColourFollowsPaceAgainstEvenUse() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func window(_ used: Double, daysLeft: Double) -> ClaudeUsage.Window {
            let reset = now.addingTimeInterval(daysLeft * 86400)
            return .init(utilization: used, resetsAt: ISO8601DateFormatter().string(from: reset))
        }
        // Half the week gone (3.5 days left): even use is 50%.
        XCTAssertEqual(ClaudeUsageFormat.paceLevel(window(40, daysLeft: 3.5), now: now), .low)
        XCTAssertEqual(ClaudeUsageFormat.paceLevel(window(50, daysLeft: 3.5), now: now), .low)
        XCTAssertEqual(ClaudeUsageFormat.paceLevel(window(55, daysLeft: 3.5), now: now), .medium)
        XCTAssertEqual(ClaudeUsageFormat.paceLevel(window(60, daysLeft: 3.5), now: now), .medium)
        XCTAssertEqual(ClaudeUsageFormat.paceLevel(window(61, daysLeft: 3.5), now: now), .high)
        // Week just started: any real use is ahead of pace.
        XCTAssertEqual(ClaudeUsageFormat.paceLevel(window(30, daysLeft: 7), now: now), .high)
        // Reset passed: the whole week counts as gone.
        XCTAssertEqual(ClaudeUsageFormat.paceLevel(window(99, daysLeft: -1), now: now), .low)
        // No reset time: the fixed buckets.
        XCTAssertEqual(ClaudeUsageFormat.paceLevel(.init(utilization: 60, resetsAt: nil), now: now), .medium)
    }

    func testSessionColourFollowsPaceAcrossFiveHours() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func window(_ used: Double, hoursLeft: Double) -> ClaudeUsage.Window {
            .init(utilization: used, resetsAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(hoursLeft * 3600)))
        }
        let length = ClaudeUsageFormat.session
        // 2.5 hours gone: even use is 50%.
        XCTAssertEqual(ClaudeUsageFormat.paceLevel(window(50, hoursLeft: 2.5), length: length, now: now), .low)
        XCTAssertEqual(ClaudeUsageFormat.paceLevel(window(60, hoursLeft: 2.5), length: length, now: now), .medium)
        XCTAssertEqual(ClaudeUsageFormat.paceLevel(window(61, hoursLeft: 2.5), length: length, now: now), .high)
        // 4 hours left: 20% gone, so 40% used is far ahead of a 5-hour pace...
        XCTAssertEqual(ClaudeUsageFormat.paceLevel(window(40, hoursLeft: 4), length: length, now: now), .high)
        // ...but behind a week's, which is nearly all gone at that reset.
        XCTAssertEqual(ClaudeUsageFormat.paceLevel(window(40, hoursLeft: 4), now: now), .low)
    }

    func testResetsIn() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func at(_ seconds: TimeInterval) -> String {
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: now.addingTimeInterval(seconds))
        }
        XCTAssertEqual(ClaudeUsageFormat.resetIn(nil, now: now), "—")
        XCTAssertEqual(ClaudeUsageFormat.resetIn("not a date", now: now), "—")
        XCTAssertEqual(ClaudeUsageFormat.resetIn(at(-60), now: now), "now")
        XCTAssertEqual(ClaudeUsageFormat.resetIn(at(0), now: now), "now")
        XCTAssertEqual(ClaudeUsageFormat.resetIn(at(59), now: now), "0m")
        XCTAssertEqual(ClaudeUsageFormat.resetIn(at(45 * 60), now: now), "45m")
        XCTAssertEqual(ClaudeUsageFormat.resetIn(at(3 * 3600), now: now), "3h")
        XCTAssertEqual(ClaudeUsageFormat.resetIn(at(3 * 3600 + 12 * 60 + 30), now: now), "3h 12m")
        XCTAssertEqual(ClaudeUsageFormat.resetIn(at(2 * 86400 + 5 * 3600 + 59 * 60), now: now), "2d 5h")
        // Six fractional digits and an offset, as Anthropic sends them.
        XCTAssertEqual(ClaudeUsageFormat.resetIn("1970-01-12T13:46:40.999999+00:00", now: now), "now")
        XCTAssertEqual(ClaudeUsageFormat.resetIn("1970-01-12T14:46:40.5+01:00", now: now), "now")
        XCTAssertEqual(ClaudeUsageFormat.resetIn("1970-01-12T12:47:40.123456-01:00", now: now), "1m")
    }

    // MARK: Fetching

    private func client(_ http: HTTPTransport, token: String? = "token-1", sleep: @escaping InvalidateSync.Sleep = InvalidateSync.taskSleep) -> ClaudeUsageClient {
        let api = HappyAPI(serverURL: testServer, clientID: "ios/9.9.9", transport: http)
        return ClaudeUsageClient(api: token.map(api.authenticated(token:)) ?? api, sleep: sleep)
    }

    func testItAsksWithTheTokenAndClientId() async throws {
        let http = FakeHTTP()
        http.onRaw("GET /v1/account/anthropic/usage", body)
        let result = await client(http).fetch()
        guard case .success(let usage) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(usage.fiveHour.utilization, 42.4)
        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.absoluteString, "https://api.example.test/v1/account/anthropic/usage")
        XCTAssertEqual(request.headers["Authorization"], "Bearer token-1")
        XCTAssertEqual(request.headers["X-Happy-Client"], "ios/9.9.9")
    }

    func testEveryFailureHasItsWords() async {
        let http = FakeHTTP()
        http.onRaw("GET /v1/account/anthropic/usage", #"{"error":"no token"}"#, status: 404)
        let failure1 = await client(http).fetch().failure
        XCTAssertEqual(failure1, .notConnected)
        http.onRaw("GET /v1/account/anthropic/usage", "", status: 502)
        let failure2 = await client(http).fetch().failure
        XCTAssertEqual(failure2, .server(502))
        http.onRaw("GET /v1/account/anthropic/usage", "", status: 401)
        let failure3 = await client(http).fetch().failure
        XCTAssertEqual(failure3, .server(401), "the fork says any non-OK status")
        http.onRaw("GET /v1/account/anthropic/usage", "not json")
        let failure4 = await client(http).fetch().failure
        XCTAssertEqual(failure4, .unreachable)
        http.on("GET /v1/account/anthropic/usage") { _ in throw URLError(.cannotConnectToHost) }
        let failure5 = await client(http).fetch().failure
        XCTAssertEqual(failure5, .unreachable)
        let failure6 = await client(http, token: nil).fetch().failure
        XCTAssertEqual(failure6, .notLoggedIn)
        let failure7 = await client(Hanging(), sleep: { _ in }).fetch().failure
        XCTAssertEqual(failure7, .timedOut)

        XCTAssertEqual(ClaudeUsageClient.Failure.notLoggedIn.text, "Not logged in")
        XCTAssertEqual(ClaudeUsageClient.Failure.notConnected.text, "Anthropic account not connected")
        XCTAssertEqual(ClaudeUsageClient.Failure.server(500).text, "Server error 500")
        XCTAssertEqual(ClaudeUsageClient.Failure.timedOut.text, "Timed out")
        XCTAssertEqual(ClaudeUsageClient.Failure.unreachable.text, "Unreachable")
        XCTAssertEqual(ClaudeUsageClient.timeout, .seconds(5))
        XCTAssertEqual(ClaudeUsageMonitor.interval, .seconds(60))
    }

    func testThePollFetchesNowAndOnRefresh() async throws {
        let http = FakeHTTP()
        http.onRaw("GET /v1/account/anthropic/usage", "", status: 500)
        let states = StateLog()
        // The interval never ends: only `start` and `refresh` fetch.
        let monitor = ClaudeUsageMonitor(client: client(http), sleep: { _ in try await Task.sleep(for: .seconds(3600)) }) { states.append($0) }
        let latest8 = await monitor.latest
        XCTAssertEqual(latest8, .loading)
        await monitor.start()
        await monitor.settled()
        let latest9 = await monitor.latest
        XCTAssertEqual(latest9, .failed("Server error 500"))

        http.onRaw("GET /v1/account/anthropic/usage", body)
        await monitor.refresh()
        await monitor.settled()
        let loaded = await monitor.latest
        guard case .loaded(let usage) = loaded else { return XCTFail("not loaded") }
        XCTAssertEqual(usage.sevenDay?.utilization, 81)
        await monitor.refresh()
        await monitor.settled()
        await monitor.stop()
        XCTAssertEqual(states.values.count, 2, "an unchanged answer is not said again")
        XCTAssertEqual(http.requests.count, 3)
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}

/// A server that never answers, until cancelled.
private struct Hanging: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await Task.sleep(for: .seconds(3600))
        return HTTPResponse(status: 200, body: Data())
    }
}

private final class StateLog: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [ClaudeUsageState] = []
    var values: [ClaudeUsageState] { lock.withLock { states } }
    func append(_ state: ClaudeUsageState) { lock.withLock { states.append(state) } }
}
