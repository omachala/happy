import Foundation
import HappyWire

/// The account-wide Anthropic usage the fork's server proxies
/// (`GET /v1/account/anthropic/usage`, useClaudeUsage.ts): the 5-hour and
/// weekly windows, and the monthly extra usage when it is on.
/// Utilization is 0–100; credits are cents.
public struct ClaudeUsage: Equatable, Sendable {
    public struct Window: Equatable, Sendable {
        public var utilization: Double
        /// ISO 8601 as the server sends it; nil when it doesn't say.
        public var resetsAt: String?

        public init(utilization: Double, resetsAt: String?) {
            self.utilization = utilization
            self.resetsAt = resetsAt
        }
    }

    public struct Extra: Equatable, Sendable {
        public var utilization: Double
        public var usedCents: Double
        public var limitCents: Double

        public init(utilization: Double, usedCents: Double, limitCents: Double) {
            self.utilization = utilization
            self.usedCents = usedCents
            self.limitCents = limitCents
        }
    }

    public var fiveHour: Window
    public var sevenDay: Window
    /// Nil unless `extra_usage.is_enabled`.
    public var extra: Extra?

    public init(fiveHour: Window, sevenDay: Window, extra: Extra? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.extra = extra
    }

    /// The body as useClaudeUsage.ts reads it: anything missing is 0 or
    /// null, never a failure.
    public init(json: JSONValue) {
        func number(_ value: JSONValue?) -> Double {
            if let number = value?.numberValue { return number }
            if let text = value?.stringValue, let number = Double(text) { return number }
            return 0
        }
        func window(_ value: JSONValue?) -> Window {
            Window(utilization: number(value?["utilization"]), resetsAt: value?["resets_at"]?.stringValue)
        }
        fiveHour = window(json["five_hour"])
        sevenDay = window(json["seven_day"])
        let extra = json["extra_usage"]
        self.extra = extra?["is_enabled"]?.boolValue == true
            ? Extra(utilization: number(extra?["utilization"]), usedCents: number(extra?["used_credits"]), limitCents: number(extra?["monthly_limit"]))
            : nil
    }
}

/// What the pill shows.
public enum ClaudeUsageState: Equatable, Sendable {
    /// Before the first answer: "Loading…".
    case loading
    case loaded(ClaudeUsage)
    /// The words the pill shows in place of a number.
    case failed(String)
}

/// UsagePill.tsx's words and buckets.
public enum ClaudeUsageFormat {
    /// The pill's and sheet's colour bucket.
    public enum Level: Equatable, Sendable {
        /// Under 50: green.
        case low
        /// 50 to under 80: orange.
        case medium
        /// 80 and up: red.
        case high
    }

    public static func level(_ percent: Double) -> Level {
        if percent >= 80 { return .high }
        if percent >= 50 { return .medium }
        return .low
    }

    /// `Math.round`, as "42%".
    public static func percent(_ value: Double) -> String {
        "\(Int((value + 0.5).rounded(.down)))%"
    }

    /// A bar's fill, 0 to 1.
    public static func fraction(_ percent: Double) -> Double {
        min(max(percent, 0), 100) / 100
    }

    /// `fmtResetIn`: "—" when unknown, "now" once past, then minutes,
    /// hours and minutes, or days and hours.
    public static func resetIn(_ resetsAt: String?, now: Date) -> String {
        guard let resetsAt else { return "—" }
        guard let date = parseDate(resetsAt) else { return "—" }
        let ms = (date.timeIntervalSince(now) * 1000).rounded(.down)
        if ms <= 0 { return "now" }
        let minutes = Int(ms / 60_000)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours < 24 { return remainder > 0 ? "\(hours)h \(remainder)m" : "\(hours)h" }
        return "\(hours / 24)d \(hours % 24)h"
    }

    /// "$12.34 / $50.00".
    public static func extraSpend(_ extra: ClaudeUsage.Extra) -> String {
        "$\(dollars(extra.usedCents)) / $\(dollars(extra.limitCents))"
    }

    static func dollars(_ cents: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), cents / 100)
    }

    /// ISO 8601 with or without fractional seconds (Anthropic sends six
    /// digits, which the formatter's own fractional option refuses).
    static func parseDate(_ text: String) -> Date? {
        var trimmed = text
        if let dot = trimmed.firstIndex(of: "."), dot > trimmed.startIndex {
            var end = trimmed.index(after: dot)
            while end < trimmed.endIndex, trimmed[end].isNumber { end = trimmed.index(after: end) }
            trimmed.removeSubrange(dot..<end)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }
}

/// One fetch of the usage, as useClaudeUsage.ts makes it: the account's
/// token and client id, five seconds at most.
public struct ClaudeUsageClient: Sendable {
    public static let path = "/v1/account/anthropic/usage"
    public static let timeout: Duration = .seconds(5)

    public enum Failure: Error, Equatable, Sendable {
        case notLoggedIn
        case notConnected
        case server(Int)
        case timedOut
        case unreachable

        /// The pill's words.
        public var text: String {
            switch self {
            case .notLoggedIn: "Not logged in"
            case .notConnected: "Anthropic account not connected"
            case .server(let status): "Server error \(status)"
            case .timedOut: "Timed out"
            case .unreachable: "Unreachable"
            }
        }
    }

    let api: HappyAPI
    let timeout: Duration
    let sleep: InvalidateSync.Sleep

    public init(api: HappyAPI, timeout: Duration = Self.timeout, sleep: @escaping InvalidateSync.Sleep = InvalidateSync.taskSleep) {
        self.api = api
        self.timeout = timeout
        self.sleep = sleep
    }

    public func fetch() async -> Result<ClaudeUsage, Failure> {
        let request: HTTPRequest
        do {
            request = try api.makeRequest("GET", Self.path)
        } catch {
            return .failure(.notLoggedIn)
        }
        let transport = api.transport
        let (timeout, sleep) = (timeout, sleep)
        return await withTaskGroup(of: Result<ClaudeUsage, Failure>?.self) { group in
            group.addTask {
                do {
                    let response = try await transport.send(request)
                    guard (200..<300).contains(response.status) else {
                        return .failure(response.status == 404 ? .notConnected : .server(response.status))
                    }
                    return .success(ClaudeUsage(json: try JSONValue.decode(response.body)))
                } catch {
                    // Cancelled because the timeout won: its answer stands.
                    return Task.isCancelled ? nil : .failure(.unreachable)
                }
            }
            group.addTask {
                do { try await sleep(timeout) } catch { return nil }
                return .failure(.timedOut)
            }
            var outcome: Result<ClaudeUsage, Failure> = .failure(.unreachable)
            for await result in group {
                guard let result else { continue }
                outcome = result
                break
            }
            group.cancelAll()
            return outcome
        }
    }
}

/// The pill's poll (useClaudeUsage.ts): one fetch now and every 60 seconds,
/// and one more whenever the pill asks (`refresh`). A newer fetch replaces
/// one still on its way. Runs off the main thread; `onChange` hears each
/// state that differs from the last.
public actor ClaudeUsageMonitor {
    public static let interval: Duration = .seconds(60)

    private let client: ClaudeUsageClient
    private let interval: Duration
    private let sleep: InvalidateSync.Sleep
    private let onChange: @Sendable (ClaudeUsageState) -> Void
    private var state = ClaudeUsageState.loading
    private var ticker: Task<Void, Never>?
    private var current: Task<Void, Never>?
    private var generation = 0

    public init(
        client: ClaudeUsageClient,
        interval: Duration = ClaudeUsageMonitor.interval,
        sleep: @escaping InvalidateSync.Sleep = InvalidateSync.taskSleep,
        onChange: @escaping @Sendable (ClaudeUsageState) -> Void
    ) {
        self.client = client
        self.interval = interval
        self.sleep = sleep
        self.onChange = onChange
    }

    public var latest: ClaudeUsageState { state }

    /// Fetches now, then on every interval until `stop`.
    public func start() {
        guard ticker == nil else { return }
        refresh()
        let (interval, sleep) = (interval, sleep)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await sleep(interval) } catch { return }
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    /// Fetches again now; the answer of any earlier fetch is dropped.
    public func refresh() {
        current?.cancel()
        generation += 1
        let token = generation
        let client = client
        current = Task { [weak self] in
            let result = await client.fetch()
            guard !Task.isCancelled else { return }
            await self?.land(result, generation: token)
        }
    }

    /// Waits for the fetch on its way, if any (tests).
    public func settled() async {
        await current?.value
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
        current?.cancel()
        current = nil
    }

    private func land(_ result: Result<ClaudeUsage, ClaudeUsageClient.Failure>, generation token: Int) {
        guard token == generation else { return }
        let next: ClaudeUsageState
        switch result {
        case .success(let usage): next = .loaded(usage)
        case .failure(let failure): next = .failed(failure.text)
        }
        guard next != state else { return }
        state = next
        onChange(next)
    }
}
