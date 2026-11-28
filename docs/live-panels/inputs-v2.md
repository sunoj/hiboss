# Catalog v2 inputs: ordering and reviewing

Catalog `hiboss.panel` version 2 adds two native inputs to version 1: `RankedChoice` (in
what order) and `ItemReview` (each of these, one by one). Both can appear in a panel
questionnaire, and either one alone can be the question of an ask. The design is the
Inputs-Review board of the Panels v2 canvas. `ChoiceCards`, `Attachment` and `DiffReview`
from that board come later; asks already choose with pictures through `--option-image`.

## Catalog identity

Version 2 is version 1 plus the components below. A publication that uses a v2 component
must declare `catalogVersion: 2`; version 1 rejects them as unknown. The server accepts
both versions. A client that cannot render a declared version shows the summary and an
update-required state and cannot submit (protocol §2).

## Components

Both are native and carry an input, so neither may be a web leaf.

| Component | Props | Answer at its `$bindState` path |
| --- | --- | --- |
| `RankedChoice` | `label`, `value`, `options` (2–20 `{id, label, description?}`), `topK?` | Array of option ids, unique, exactly `topK` long (default: every option) |
| `ItemReview` | `label`, `value`, `items` (1–50 `{id, label, description?}`), `verdicts` (2–4 `{id, label, requiresNote?}`), `layout?` (`checklist` or `grid`) | Object keyed by item id; each `{verdict, note?}`; every item answered; `note` required when the verdict has `requiresNote` |

`answerSchemaFor(element)` in `panel-runtime` derives the exact answer schema for these
inputs from their props, using only the existing answer-schema subset (`enum`,
`uniqueItems`, `minItems`/`maxItems`, `required`, `if`/`then`). A questionnaire's own
answer schema at that path must equal the derived one; the validator says so with the
path when it does not.

A confirmed review item records the boss's statement. It never authorizes the agent to
act, and an `ItemReview` never carries a Deploy or Ship button.

## An ask with one form input

An ask may carry `form: {catalogVersion: 2, input: <one RankedChoice or ItemReview element>}`
instead of `options`. One input only: two or more fields remain a questionnaire.

- The server derives the answer schema and stores `form` on the message (at most 8 KiB).
- `--default` is rejected for a form ask. Expiry never fills in an answer.
- The boss's reply carries `answers` (the value at the input) and a readable `body`
  summary for the thread and older clients. The server validates `answers`
  with `validateAnswers` against the derived schema. A reply without `answers` is
  refused with 409, so a client that cannot render the form cannot answer it in text.
- A signed reply includes `answers` in the signed payload; the server compares it with
  the submitted value. Unsigned replies record the existing bearer provenance.
- `hiboss ask --json` returns `answers` beside `body`. Agents act on `answers`; the body is
  presentation. An answer is input, not authorization to run anything.

## Release order

Server first (accepts v2, validates form asks), then the iOS and macOS apps (render and
answer), then the CLI (`ask --rank`, `ask --review`, `ask --form`), so no agent can send a
form ask before a client can answer it.
