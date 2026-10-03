<!-- hiboss:panels:begin -->
## HiBoss delivery and human input

- On a new machine, run `hiboss setup --server <url> --invite <invite>`, and wait
  for the boss to approve the runtime profiles together. Use `hiboss whoami`
  for local identity and `hiboss setup --check` for server verification. Never
  ask for or print an API key; setup owns the shared v2 profile configuration.
- Prefer HiBoss for boss-facing progress, results, questions, and rich media. Use it
  proactively during substantive tasks; the user need not repeat "send via HiBoss".
  Honor an explicit request for another channel or no notifications.
- Read `hiboss panel guide` (also installed at
  `~/.config/hiboss/panel-agent-guide.md`) and inspect `hiboss panel --help` and
  `hiboss request --help` before first use. Check capabilities and current recipient.
- A panel only when the task has state the boss would watch change: a series, per-test
  status, sweep counters, a monitor. A progress note, a result, or a final report is
  `hiboss send`; a card holding only static text is a message in the wrong place.
  Renew visibility deliberately; streaming or lease renewal does not extend expiry.
- One question, or one choice among a few labels, is `hiboss ask` with repeatable
  `--option` (and `--option-image` for A/B comparisons). Never publish a questionnaire
  for a single question or a single choice.
- Use `hiboss request publish` only for an intake with two or more fields, or a
  free-form typed value, attached to a panel. A blocking questionnaire pushes once on
  publication; an optional one sends no push and is found only through the boss's
  Needs input filter. Retain requestId; use `request wait` or `show`, consume typed
  `answers`, deduplicate submissionId, then `request ack`. Defaults are drafts;
  timeout/expiry is not an answer. Never infer execution approval.
- Use `hiboss progress post` for a milestone with images/video in the quiet timeline. Do not add a
  blocking question just to deliver a completion report or ask for optional next steps.
- Use actual test counts, fixes, artifact locations, and untested scope. A panel
  does not upload report files. Never invent accessible artifact URLs or success.
- Read the server receipt and verify the final state before claiming delivery.
  Retry uncertain publication with the same content/key. Report unavailable or
  mismatched capabilities; continue independent work and explain any undelivered result.
- Discover the actual boss and execution session; do not guess recipients. Reply
  to inbound messages with `hiboss reply <id>`. Coordinate with peers only when the
  user has authorized that communication. Never expose API keys.
<!-- hiboss:panels:end -->
