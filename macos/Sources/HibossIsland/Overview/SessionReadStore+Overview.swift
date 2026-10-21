// Applies HibossKit's shared session-unread rule to the sessions the Mac sidebar lists.
// Exports: SessionReadStore.unreadSessionIDs(in:) for an OverviewSnapshot.
// Dependencies: HibossKit SessionReadStore and the Overview snapshot's session directory.

import HibossKit

extension SessionReadStore {
    func unreadSessionIDs(in snapshot: OverviewSnapshot) -> Set<String> {
        let directory = snapshot.today.sessionDirectory
        let listed = Set((directory.needsYou + directory.working + directory.idle).map(\.id))
        return unreadSessionIDs(messages: snapshot.history).intersection(listed)
    }
}
