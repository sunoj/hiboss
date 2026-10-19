<!-- Box collections and likes: boss-named groups of Box items and a per-item like mark.
     Scope: data model, HTTP API, CLI flags, HibossKit models, iOS and macOS surfaces. -->
# Box collections and likes

Extends `docs/hiboss-box-design.md` (data model, access) and `docs/box-v2.md` (native
surfaces). Everything there still applies.

## Concepts

- **Like (喜欢)**: a boss-only mark on one item. An item is liked or not; there is no count.
  Agents read the mark and filter by it, so the boss can say "use the images I liked".
- **Collection (集合)**: a named group of items in one boss's Box, created by the boss or an agent, like a photo album. An item can be in
  any number of collections. Deleting a collection never deletes its items. A soft-deleted
  item keeps its memberships but is hidden everywhere (lists, counts, covers); a purge removes
  them.

## Data model (migration `0056_box_collections.sql`)

- `box_items.liked_at TEXT NULL`: set when liked, NULL otherwise. Index
  `(boss_id, deleted_at, liked_at)`.
- `box_collections(id TEXT PRIMARY KEY, boss_id TEXT NOT NULL REFERENCES bosses(id),
  name TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)` with a unique index
  on `(boss_id, name COLLATE NOCASE)`. IDs are `bc_` + random hex.
- `box_collection_items(collection_id TEXT NOT NULL REFERENCES box_collections(id) ON DELETE
  CASCADE, item_id TEXT NOT NULL REFERENCES box_items(id) ON DELETE CASCADE, added_at TEXT NOT
  NULL, PRIMARY KEY (collection_id, item_id))` with an index on `item_id`.
- Name: trimmed, 1–64 characters, no control characters. At most 200 collections per boss.
- A purge deletes the item's membership rows explicitly in the same batch, not relying on
  cascades alone.
- Like is idempotent: `SET liked_at = COALESCE(liked_at, ?)`, so a repeated like keeps the
  original timestamp.

## Item response

Every item response (list, latest, search, show, create, patch) gains:

| Field | Type | Notes |
|---|---|---|
| `liked` | boolean | |
| `liked_at` | ISO 8601 or null | |
| `collection_ids` | string array | IDs of the collections holding the item, oldest membership first |

Older clients ignore the new fields; new clients treat absent fields as `false`/`null`/`[]`.

## API

| Method and path | Caller | Effect |
|---|---|---|
| `PUT /api/box/items/:id/like` | boss | Like; idempotent; returns the item |
| `DELETE /api/box/items/:id/like` | boss | Unlike; idempotent; returns the item |
| `GET /api/box/collections` | boss, agent | `{"collections":[…]}` for the readable bosses, ordered by boss name, then name |
| `POST /api/box/collections` | boss, agent | `{"name", "boss"?}` → 201 collection; 409 on a duplicate name |
| `PATCH /api/box/collections/:id` | boss, agent | `{"name"}` → renamed collection; 409 on a duplicate |
| `DELETE /api/box/collections/:id` | boss | 204; items untouched |
| `PUT /api/box/collections/:id/items/:item_id` | boss, agent | Add; idempotent; returns the item |
| `DELETE /api/box/collections/:id/items/:item_id` | boss, agent | Remove; idempotent; returns the item |

Agents organize collections for the bosses they can read: they create and rename collections and
add or remove any live item of that boss, whoever added it. On create, `boss` (id or name)
picks the boss the way `box add --boss` does: optional when the agent reads one boss, 409 naming
the choices when it reads several, 404 when unknown. Deleting a collection and liking stay
boss-only; an agent attempting them, or touching a collection or item of a boss it cannot read,
gets 404, matching the existing Box access rule that hides what a caller cannot touch.

Collection object: `id`, `boss_id`, `boss_name`, `name`, `item_count` (live items only),
`cover_item_id` (newest live image or video item, else null), `created_at`, `updated_at`.

The collection and the item must belong to the same boss, else 404.

List, latest and search accept two more filters, combinable with the existing ones:

- `liked=1`: liked items only.
- `collection=<id or name>`: items in that collection. A name matches case-insensitively
  within the readable bosses; an ambiguous name across several bosses returns 409 naming the
  choices, an unknown one 404.

Order stays newest-first by `created_at` in every case, including inside a collection.

## CLI

- `hiboss box list|latest|search … --liked --collection <name|id>`.
- `hiboss box collections [--boss <id|name>] [--json]` lists collections with counts.
- `hiboss box add … --collection <name|id>` (repeatable) puts the new item into existing
  collections. Names are resolved before the item is created: an unknown name fails with the
  list of valid names and creates nothing.
- `hiboss box collections new <name> [--boss <id|name>]` creates a collection and prints it.
- `hiboss box collections rename <name|id> <new-name> [--boss <id|name>]` renames one.
- `hiboss box collections add|rm <name|id> <item-id>… [--boss <id|name>]` adds or removes items;
  each item is applied in order and the command stops at the first failure, naming it.
  `--boss` disambiguates a collection name shared by several bosses.
- Text output marks liked items with `♥` and prints collection names on the metadata line.

Deleting collections and liking happen in the native apps; the CLI has no command for
either.

## Code layout

- `server/src/box/` is at the 10-file module limit. Like routes go in `items.ts`, like store
  operations in `store.ts`, the `liked`/`collection` clauses in `filters.ts`. Everything
  collection-shaped (routes, store, validation, tests) lives in a new
  `server/src/box/collections/` module mounted from `items.ts`.
- `cli/src/commands/box/` is at 9 files; collection code goes in a `box/collections/`
  submodule.
- The iOS liked filter is a client-side predicate like `BoxFilter.matches`; a collection scope
  is a server-side `collection=` query, because memberships of unloaded pages are unknown.

## HibossKit

- `BoxItem` gains `liked: Bool`, `likedAt: String?`, `collectionIDs: [String]` (decoded
  leniently, see Item response).
- New `BoxCollection` model (`Codable, Identifiable, Sendable`) and API calls:
  `boxCollections()`, `createBoxCollection(name:)`, `renameBoxCollection(id:name:)`,
  `deleteBoxCollection(id:)`, `setBoxItem(id:liked:)`, `setBoxItem(id:inCollection:member:)`,
  and the `liked`/`collection` query options on list and search.
- The iOS view currently named `BoxCollection` (`ios/App/Box/BoxCollection.swift`, the
  sectioned list/grid) is renamed `BoxResultsView` so the model owns the name.

## iOS

- Like: a heart button in the detail action group and the media viewer's bottom bar; a leading
  swipe action and a context-menu item on list rows; liked rows and cards show a small filled
  heart beside the metadata line. Toggling updates optimistically and rolls back with an
  inline error on failure.
- The filter bar gains a **已喜欢 (Liked)** toggle chip, combinable with kind and author.
- Collections: a **集合** entry at the top of the Box list opens a collection grid (cover
  thumbnail, name, count) with New, Rename and Delete (Delete confirms and states that items
  stay in the Box). Opening one shows the usual Box list scoped to it, with the same filters.
- "加入集合…" in the detail actions and row context menu opens a checklist sheet of
  collections with a New collection row; checking and unchecking applies immediately.
- The detail information group lists the item's collections.

## macOS

- Sidebar of the Box window: **全部**, **已喜欢**, then a **集合** section listing collections
  with counts, a + button, and context-menu Rename/Delete. Selecting one scopes the list.
- Rows can be dragged onto a sidebar collection to add them.
- Detail pane and row context menu: a heart toggle (⌘L) and an "加入集合" submenu with
  checkmarks and "新建集合…".

## Shared vocabulary

喜欢 / 取消喜欢 / 已喜欢 (Like / Unlike / Liked); 集合 / 新建集合 / 加入集合… / 重命名 /
删除集合 (Collection / New Collection / Add to Collection… / Rename / Delete Collection).
