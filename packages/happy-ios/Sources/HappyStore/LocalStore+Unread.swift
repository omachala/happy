import Foundation
import GRDB

extension LocalStore {
    /// sync.ts `session-event` → storage.ts `markSessionUnread`: the server
    /// says this one session finished a turn, wants a permission or asks
    /// something. The caller has already left out the chat on screen.
    /// Lasts until the chat is read (`markSessionRead`) or the next launch.
    public func markSessionUnread(id: String) throws {
        try performWrite { db in
            try db.execute(sql: "UPDATE session SET unread = 1 WHERE id = ? AND unread = 0", arguments: [id])
        }
    }
}
