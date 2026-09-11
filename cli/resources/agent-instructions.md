<!-- hiboss:panels:begin -->
## HiBoss delivery and human input

- Prefer HiBoss for boss-facing progress, results, questions, and rich media. Use it
  proactively during substantive tasks; the user need not repeat "send via HiBoss".
  Honor an explicit request for another channel or no notifications.
- Read `hiboss panel guide` (also installed at
  `~/.config/hiboss/panel-agent-guide.md`) and inspect `hiboss panel --help` and
  `hiboss request --help` before first use. Check capabilities and current recipient.
- Use one `hiboss panel` per execution for ongoing progress and final test/report
  delivery. Publish early, update at meaningful milestones, and finish the same card.
  Renew visibility deliberately; streaming or lease renewal does not extend expiry.
- Prefer `hiboss request publish` for multi-field intake, requirements, preferences,
  and structured answers attached to a panel. Retain requestId; use `request wait`
  or `show`, consume typed `answers`, deduplicate submissionId, then `request ack`.
  Defaults are drafts; timeout/expiry is not an answer. Never infer execution approval.
- Use `hiboss send` for a one-shot notice or urgent blocker; use `hiboss progress
  post` for a milestone with images/video in the quiet timeline. Use `hiboss ask`
  only for a required decision or a short choice, including A/B image comparisons
  with repeatable `--option` and `--option-image`. Do not add a blocking question
  just to deliver a completion report or ask for optional next steps.
- Use actual test counts, fixes, artifact locations, and untested scope. A panel
  does not upload report files. Never invent accessible artifact URLs or success.
- Read the server receipt and verify the final state before claiming delivery.
  Retry uncertain publication with the same content/key. Report unavailable or
  mismatched capabilities; continue independent work and explain any undelivered result.
- Discover the actual boss and execution session; do not guess recipients. Reply
  to inbound messages with `hiboss reply <id>`. Coordinate with peers only when the
  user has authorized that communication. Never expose API keys.
<!-- hiboss:panels:end -->
