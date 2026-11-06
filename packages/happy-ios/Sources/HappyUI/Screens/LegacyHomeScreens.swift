#if canImport(UIKit)
import HappyCore
import HappyLayout
import UIKit

/// UsagePill.tsx `UsageSheet`, as a sheet with the standard bar: "Claude
/// usage" over "Anthropic account-wide", then the 5-hour and weekly
/// windows, and the month's extra usage when it is on. Each has its
/// percentage in its bucket's colour and a bar.
final class ClaudeUsageSheetViewController: UIViewController {
    @MainActor
    private final class SectionViews {
        let label = StyledLabel(style: TextStyles.usageSheetLabel, color: Palette.text, lines: 1)
        let percent = StyledLabel(style: TextStyles.usageSheetPercent, color: Palette.text, lines: 1)
        let track = UIView()
        let fill = UIView()
        let detail = StyledLabel(style: TextStyles.usageSheetDetail, color: Palette.textSecondary, lines: 1)
        let fraction: Double

        init(fraction: Double) { self.fraction = fraction }
    }

    private let subtitle = StyledLabel(style: TextStyles.usageSheetSubtitle, color: Palette.textSecondary, lines: 0)
    private let divider = UIView()
    private var sections: [SectionViews] = []

    init(usage: ClaudeUsage, now: Date = Date()) {
        super.init(nibName: nil, bundle: nil)
        title = Strings.LegacyHome.usageTitle
        subtitle.string = Strings.LegacyHome.usageSubtitle
        func section(_ label: String, _ percent: Double, _ detail: String) -> SectionViews {
            let views = SectionViews(fraction: ClaudeUsageFormat.fraction(percent))
            views.label.string = label
            views.percent.string = ClaudeUsageFormat.percent(percent)
            views.percent.color = UsagePillView.color(percent)
            views.fill.backgroundColor = UIColor(UsagePillView.color(percent))
            views.detail.string = detail
            return views
        }
        sections = [
            section(Strings.LegacyHome.usageSession, usage.fiveHour.utilization, Strings.LegacyHome.resetsIn(ClaudeUsageFormat.resetIn(usage.fiveHour.resetsAt, now: now))),
            section(Strings.LegacyHome.usageWeekly, usage.sevenDay.utilization, Strings.LegacyHome.resetsIn(ClaudeUsageFormat.resetIn(usage.sevenDay.resetsAt, now: now))),
        ]
        if let extra = usage.extra {
            sections.append(section(Strings.LegacyHome.usageExtra, extra.utilization, ClaudeUsageFormat.extraSpend(extra)))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(Palette.surface)
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        divider.backgroundColor = UIColor(Palette.divider)
        view.addSubview(subtitle)
        view.addSubview(divider)
        for section in sections {
            section.track.backgroundColor = UIColor(Palette.claudeUsageTrack)
            section.track.layer.cornerRadius = UsageSheetLayout.Metrics.barHeight / 2
            section.track.clipsToBounds = true
            section.fill.layer.cornerRadius = UsageSheetLayout.Metrics.barHeight / 2
            section.track.addSubview(section.fill)
            for view in [section.label, section.percent, section.track, section.detail] as [UIView] { view.isUserInteractionEnabled = false; self.view.addSubview(view) }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let layout = UsageSheetLayout(
            width: view.bounds.width,
            top: view.safeAreaInsets.top,
            hairline: view.hairline,
            subtitle: subtitle.measurable,
            sections: sections.map { .init(label: $0.label.measurable, percent: $0.percent.measurable, detail: $0.detail.measurable) }
        )
        subtitle.setLayoutFrame(layout.subtitle)
        divider.frame = layout.divider
        for (views, frames) in zip(sections, layout.sections) {
            views.label.setLayoutFrame(frames.label)
            views.percent.setLayoutFrame(frames.percent)
            views.track.setLayoutFrame(frames.track)
            let fill = frames.fill(views.fraction)
            views.fill.frame = CGRect(origin: .zero, size: fill.size)
            views.detail.setLayoutFrame(frames.detail)
        }
    }

    /// In a sheet of its own with the standard bar.
    static func present(_ usage: ClaudeUsage, from host: UIViewController) {
        let navigation = UINavigationController(rootViewController: ClaudeUsageSheetViewController(usage: usage))
        navigation.modalPresentationStyle = .pageSheet
        navigation.sheetPresentationController?.detents = [.medium(), .large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        host.present(navigation, animated: true)
    }
}

/// connection-error.tsx: what the socket last said of itself
/// (`ConnectionErrorReport`), monospaced in a card, with a copy button in
/// the bar and a hint under it. The text follows the socket while shown.
final class ConnectionErrorViewController: UIViewController {
    private let context: AppContext
    private let session: AccountSession
    private let scroll = UIScrollView()
    private let card = UIView()
    private let details = StyledLabel(style: TextStyles.connectionDiagnostics, color: Palette.text, lines: 0)
    private let hint = StyledLabel(style: TextStyles.connectionDiagnosticsHint, color: Palette.textSecondary, lines: 0)
    private var statusWatch: Watch?
    private(set) var text = ""

    init(context: AppContext, session: AccountSession) {
        self.context = context
        self.session = session
        super.init(nibName: nil, bundle: nil)
        title = Strings.LegacyHome.connectionErrorTitle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(Palette.groupedBackground)
        minimalBackButton()
        navigationItem.largeTitleDisplayMode = .never
        let copy = UIBarButtonItem(image: .icon(.ionicons("copy-outline"), size: 22), primaryAction: UIAction { [weak self] _ in self?.copyDetails() })
        copy.accessibilityLabel = Strings.Chat.copy
        navigationItem.rightBarButtonItem = copy
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        card.backgroundColor = UIColor(Palette.surface)
        card.layer.cornerRadius = ConnectionErrorLayout.Metrics.radius
        card.layer.cornerCurve = .continuous
        details.lineBreakMode = .byCharWrapping
        details.accessibilityLabel = Strings.LegacyHome.connectionDetails
        hint.string = Strings.LegacyHome.connectionErrorHint
        card.addSubview(details)
        scroll.addSubview(card)
        scroll.addSubview(hint)
        HeaderBar.edge(scroll, in: self)
        statusWatch = LegacyLink.link(for: session).watchStatus { [weak self] status in self?.render(status) }
    }

    private func render(_ status: RealtimeStatus) {
        let server = session.api.serverURL
        text = ConnectionErrorReport.format(
            status: status,
            diagnostics: session.realtime.diagnostics.snapshot,
            client: session.api.clientID,
            server: server,
            custom: server != ServerConfig.defaultServerURL
        )
        details.string = text
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scroll.frame = view.bounds
        // The scroll view keeps itself clear of the bars; only the sides are ours.
        let sides = LayoutInsets(left: view.safeAreaInsets.left, right: view.safeAreaInsets.right)
        let layout = ConnectionErrorLayout(width: view.bounds.width, safeArea: sides, details: details.measurable, hint: hint.measurable)
        card.setLayoutFrame(layout.card)
        details.setLayoutFrame(layout.details)
        hint.setLayoutFrame(layout.hint)
        scroll.contentSize = layout.contentSize
    }

    private func copyDetails() {
        UIPasteboard.general.string = text
        Alerts.show(Strings.LegacyHome.copied, Strings.LegacyHome.copiedMessage, on: self)
    }
}
#endif
