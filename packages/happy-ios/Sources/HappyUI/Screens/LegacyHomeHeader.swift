#if canImport(UIKit)
import HappyCore
import HappyLayout
import UIKit

/// The fork's Happy CLI home header (MainView.tsx), in UIKit's own bar:
///   - left, the Happy logo, the only way to Settings;
///   - the title, no words of its own, only the socket's status (a dot and
///     its word), which opens the connection error while the socket is
///     down and something went wrong;
///   - right, the Claude usage pill, then `+` to the new-session screen on
///     the draft as it was left.
///
/// The same items stay in the bar for the account's life: a button
/// rebuilt under a finger drops its tap.
@MainActor
final class LegacyHomeHeader {
    let status = LegacyConnectionStatusView()
    let pill = UsagePillView()

    var onSettings: (() -> Void)?
    var onNewSession: (() -> Void)?
    var onConnectionError: (() -> Void)?
    var onUsage: ((ClaudeUsage) -> Void)?
    var onUsageRefresh: (() -> Void)?

    private let diagnostics: SocketDiagnostics
    private var statusWatch: Watch?

    /// header/HeaderLogo.tsx: the logo, 24 in a 32 box, in the bar's tint.
    private(set) lazy var logoItem: UIBarButtonItem = {
        let logo = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { _ in
            UIImage.happy("logo-black")?.draw(in: CGRect(x: 0, y: 0, width: 24, height: 24))
        }.withRenderingMode(.alwaysTemplate)
        let item = UIBarButtonItem(image: logo, primaryAction: UIAction { [weak self] _ in self?.onSettings?() })
        item.accessibilityLabel = Strings.LegacyHome.settings
        item.accessibilityIdentifier = "settings"
        return item
    }()

    private(set) lazy var plusItem: UIBarButtonItem = {
        let item = UIBarButtonItem(image: .icon(.ionicons("add-outline"), size: 28), primaryAction: UIAction { [weak self] _ in self?.onNewSession?() })
        item.accessibilityLabel = Strings.LegacyHome.newSession
        item.accessibilityIdentifier = "compose"
        return item
    }()

    private(set) lazy var usageItem = UIBarButtonItem(customView: pill)

    init(session: AccountSession) {
        diagnostics = session.realtime.diagnostics
        // Plain UIControls: UIKit sends them `.touchUpInside`, never
        // `.primaryActionTriggered` (only UIButton and friends do), so a tap
        // on either did nothing.
        pill.addAction(UIAction { [weak self] _ in self?.usageTapped() }, for: .touchUpInside)
        status.addAction(UIAction { [weak self] _ in
            guard let self, status.isTappable else { return }
            onConnectionError?()
        }, for: .touchUpInside)
        statusWatch = LegacyLink.link(for: session).watchStatus { [weak self] status in self?.show(status) }
    }

    func install(on item: UINavigationItem) {
        item.leftBarButtonItem = logoItem
        item.titleView = status
        // Outermost first: `+` at the edge, the pill inside it.
        item.rightBarButtonItems = [plusItem, usageItem]
    }

    /// apiSocket.ts's status and, read as it arrives, whether an error was
    /// captured: the error is recorded before the status says so.
    private func show(_ socket: RealtimeStatus) {
        let error = diagnostics.snapshot.lastError
        status.show(socket, tappable: socket != .connected && (error != nil || socket == .error))
    }

    var usage: ClaudeUsageState = .loading {
        didSet { if usage != oldValue { pill.usage = usage } }
    }

    /// With a number, the sheet; otherwise fetch again at once.
    private func usageTapped() {
        if case .loaded(let usage) = usage { onUsage?(usage) } else { onUsageRefresh?() }
    }
}

/// The status as MainView.tsx `HeaderTitle` draws it: a 6pt dot, pulsing
/// while connecting, and the status's word in its colour; a small info
/// glyph after them while a tap opens the details.
final class LegacyConnectionStatusView: UIControl {
    private let dot = StatusDotView()
    private let label = StyledLabel(style: TextStyles.legacyConnectionStatus, color: Palette.statusConnected, lines: 1)
    private let info = IconView(.ionicons("information-circle-outline"), size: LegacyConnectionStatusLayout.Metrics.infoSize)
    private(set) var isTappable = false
    private(set) var status: RealtimeStatus?

    override init(frame: CGRect) {
        super.init(frame: frame)
        for view in [dot, label, info] as [UIView] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        info.isHidden = true
        accessibilityIdentifier = "home-connection-status"
        isAccessibilityElement = true
        show(HomeConnectionStatus.initial, tappable: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ status: RealtimeStatus, tappable: Bool) {
        guard status != self.status || tappable != isTappable else { return }
        self.status = status
        isTappable = tappable
        let color = Self.color(status)
        dot.backgroundColor = UIColor(color)
        dot.isPulsing = HomeConnectionStatus.pulses(status)
        label.color = color
        label.string = Strings.Home.connectionStatus(status)
        info.tintColor = UIColor(color)
        info.isHidden = !tappable
        isEnabled = tappable
        accessibilityLabel = label.string
        accessibilityTraits = tappable ? .button : .staticText
        invalidateIntrinsicContentSize()
        frame.size = sizeThatFits(.zero)
        setNeedsLayout()
    }

    static func color(_ status: RealtimeStatus) -> ColorToken {
        switch status {
        case .connected: Palette.statusConnected
        case .connecting: Palette.statusConnecting
        case .disconnected: Palette.statusDisconnected
        case .error: Palette.statusError
        }
    }

    private func measured() -> LegacyConnectionStatusLayout {
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        return LegacyConnectionStatusLayout(text: label.sizeThatFits(unbounded), info: isTappable ? info.sizeThatFits(.zero) : nil)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { measured().size }
    override var intrinsicContentSize: CGSize { measured().size }

    override func layoutSubviews() {
        super.layoutSubviews()
        let layout = measured()
        dot.setLayoutFrame(layout.dot)
        label.setLayoutFrame(layout.text)
        if let frame = layout.info { info.setLayoutFrame(frame) }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted && isTappable ? 0.5 : 1 }
    }
}

/// UsagePill.tsx: a capsule with a dot and the 5-hour use ("42%"), or the
/// reason there is none ("Timed out"). Never hidden.
final class UsagePillView: UIControl {
    private let ground = UIView()
    private let dot = UIView()
    private let label = StyledLabel(style: TextStyles.usagePill, color: Palette.text, lines: 1)

    var usage: ClaudeUsageState = .loading {
        didSet { if usage != oldValue { render() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        ground.backgroundColor = UIColor(Palette.claudeUsagePillGround)
        ground.layer.cornerCurve = .continuous
        for view in [ground, dot, label] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        accessibilityIdentifier = "usage-pill"
        isAccessibilityElement = true
        accessibilityTraits = .button
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func render() {
        switch usage {
        case .loading:
            dot.backgroundColor = UIColor(Palette.claudeUsagePending)
            label.string = Strings.LegacyHome.usageLoading
            accessibilityHint = Strings.LegacyHome.usageRefresh
        case .failed(let reason):
            dot.backgroundColor = UIColor(Palette.claudeUsagePending)
            label.string = reason
            accessibilityHint = Strings.LegacyHome.usageRefresh
        case .loaded(let usage):
            dot.backgroundColor = UIColor(Self.color(usage.fiveHour.utilization))
            label.string = ClaudeUsageFormat.percent(usage.fiveHour.utilization)
            accessibilityHint = nil
        }
        accessibilityLabel = [Strings.LegacyHome.usageLabel, label.string].joined(separator: ", ")
        invalidateIntrinsicContentSize()
        frame.size = sizeThatFits(.zero)
        setNeedsLayout()
        superview?.setNeedsLayout()
    }

    static func color(_ percent: Double) -> ColorToken {
        switch ClaudeUsageFormat.level(percent) {
        case .low: Palette.claudeUsageLow
        case .medium: Palette.claudeUsageMedium
        case .high: Palette.claudeUsageHigh
        }
    }

    private func measured() -> UsagePillLayout {
        UsagePillLayout(text: label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { measured().size }
    override var intrinsicContentSize: CGSize { measured().size }

    override func layoutSubviews() {
        super.layoutSubviews()
        let layout = measured()
        ground.setLayoutFrame(CGRect(origin: .zero, size: layout.size))
        ground.layer.cornerRadius = layout.cornerRadius
        dot.setLayoutFrame(layout.dot)
        dot.layer.cornerRadius = UsagePillLayout.Metrics.dotSize / 2
        label.setLayoutFrame(layout.text)
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.5 : 1 }
    }
}
#endif
