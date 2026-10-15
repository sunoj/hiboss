# Thread and reaction models

`MessageThread.fold` follows loaded `reply_to` ancestry in either direction.
A message with no loaded parent is a root. Root rows keep input order.
`entries` contains every non-root member ordered by parsed `created_at`;
equal dates keep input order and unparseable dates sort first.

`replies` remains the boss-only subset in input order. Only boss replies
determine `newestReply` and the decision `outcome`. Existing initializers
remain available; when `entries` is omitted it is derived from `replies`.
Cyclic ancestry has no root, so affected messages remain standalone.

`MessageMetadata.reactions` contains valid, first-seen reactions unique by
(actor, actor ID, emoji). Duplicate entries never replace the first timestamp.
`reactionGroups` exposes each emoji's count, `bossReacted`, and
`agentReacted`, preserving the first occurrence of each emoji.

New entries use `emoji`, `actor` (boss or agent), `actor_id`, and an
ISO8601 `created_at`. Legacy `{emoji, boss_id}` and `{emoji, user}`
entries become boss reactions with no timestamp. Encoding preserves the
legacy boss shape when no timestamp exists, rather than inventing one.
Malformed entries are skipped individually; absent or malformed reaction
arrays become empty. Reaction arrays and values are immutable; the model
offers no removal operation.

## Session view layout (macOS and iOS)

Both clients render a session's messages from these models in the same order:

1. **Needs you**: open, answerable decisions, soonest auto-default deadline first, then oldest.
   A decision leaves this zone once a boss reply is recorded, even if answerability data is stale.
2. **Conversation**: one card per thread, newest last activity first, with day separators.
   Last activity is the latest `created_at` of the root, its entries and its reactions. Inside a
   card everything is chronological; agent follow-ups are compact indented rows; reactions are
   emoji chips with a count. Consecutive standalone messages from the same agent at most
   10 minutes apart merge into one card. "Details" appears only for content beyond the visible
   text. Ties break by message ID, so an identical refresh never reorders cards.
3. **Watching** keeps its existing place.

Agent acknowledgements sent before linked follow-ups existed have no `reply_to` and stay standalone.
Implementations: `macos/Sources/HibossIsland/Sessions/SessionThreadLogic.swift`,
`ios/App/Messages/SessionThreads.swift`.
