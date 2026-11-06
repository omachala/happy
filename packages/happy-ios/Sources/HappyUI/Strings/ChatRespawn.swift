import Foundation

// The composer's trash in a Happy CLI chat (the fork's kill-and-respawn).
// The fork's button has no label of its own; VoiceOver reads this one,
// English as AgentInput.tsx's literal labels are.
extension Strings {
    public enum ChatRespawn {
        /// The trash: the agent stops and a fresh one starts in its place.
        public static let trash = "Clear conversation"
    }
}
