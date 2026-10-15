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
