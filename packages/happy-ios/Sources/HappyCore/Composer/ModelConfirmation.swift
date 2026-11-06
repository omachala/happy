import Foundation

/// Whether the model chip is green: the CLI has confirmed, since the chat
/// opened, that it runs the model the chip shows (the fork's
/// hooks/useModelConfirmed.ts).
///
/// - Grey whenever a chat opens, even if the metadata already on disk
///   matches: the first value seen is taken as stale.
/// - Green once a newer metadata version arrives whose `currentAgentModel`
///   is exactly the selected key (`AgentDefaults.claudeModelKey`). The
///   fork's CLI writes it at every turn's end, so the chip turns green
///   after the first reply.
/// - A different selection goes grey and takes the metadata it sees then
///   as stale again: only a newer version can confirm it.
///
/// Once green it stays green until the selection changes, as the fork's
/// hook does.
public struct ModelConfirmation: Equatable, Sendable {
    public private(set) var isConfirmed = false
    /// The metadata version last seen; nil before the first look.
    private var seenVersion: Int?
    private var selectedKey: String?

    public init() {}

    /// The session's metadata (its version and `currentAgentModel`) and the
    /// selected model key, each time either may have changed. Returns
    /// whether `isConfirmed` changed.
    @discardableResult
    public mutating func update(metadataVersion: Int?, currentAgentModel: String?, selectedKey: String?) -> Bool {
        let before = isConfirmed
        guard let seen = seenVersion else {
            seenVersion = metadataVersion ?? -1
            self.selectedKey = selectedKey
            return false
        }
        if selectedKey != self.selectedKey {
            self.selectedKey = selectedKey
            isConfirmed = false
            seenVersion = metadataVersion ?? -1
            return before != isConfirmed
        }
        let version = metadataVersion ?? -1
        guard version != seen else { return false }
        seenVersion = version
        if let selectedKey, AgentDefaults.claudeModelKey(fromModelId: currentAgentModel) == selectedKey {
            isConfirmed = true
        }
        return before != isConfirmed
    }
}
